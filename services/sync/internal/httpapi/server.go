package httpapi

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/FelixZoe/qingxu/services/sync/internal/store"
)

const (
	maxTasksPerRequest = 10_000
	maxFutureClockSkew = 5 * time.Minute
)

var tokenPattern = regexp.MustCompile(`^[0-9a-fA-F]{64}$`)

type Config struct {
	Token          string
	AllowedOrigins []string
	MaxBodyBytes   int64
}

type Server struct {
	store        *store.Store
	tokenHash    [sha256.Size]byte
	origins      map[string]struct{}
	allowAny     bool
	maxBodyBytes int64
}

func New(config Config, taskStore *store.Store) (*Server, error) {
	if taskStore == nil {
		return nil, errors.New("task store is required")
	}
	token := strings.TrimSpace(config.Token)
	if !tokenPattern.MatchString(token) {
		return nil, errors.New("SYNC_TOKEN must contain exactly 64 hexadecimal characters")
	}
	if config.MaxBodyBytes <= 0 {
		return nil, errors.New("max body bytes must be positive")
	}

	server := &Server{
		store:        taskStore,
		tokenHash:    sha256.Sum256([]byte(token)),
		origins:      make(map[string]struct{}),
		maxBodyBytes: config.MaxBodyBytes,
	}
	for _, configured := range config.AllowedOrigins {
		origin := strings.TrimSpace(configured)
		if origin == "" {
			continue
		}
		if origin == "*" {
			server.allowAny = true
			continue
		}
		server.origins[origin] = struct{}{}
	}
	return server, nil
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", s.health)
	mux.HandleFunc("/v1/ping", s.ping)
	mux.HandleFunc("/v1/sync", s.sync)
	return s.withCORS(mux)
}

func (s *Server) ping(response http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodGet {
		response.Header().Set("Allow", http.MethodGet)
		writeError(response, http.StatusMethodNotAllowed, "method_not_allowed", "only GET is allowed")
		return
	}
	if !s.requireAuthorization(response, request) {
		return
	}
	writeJSON(response, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) health(response http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodGet {
		response.Header().Set("Allow", http.MethodGet)
		writeError(response, http.StatusMethodNotAllowed, "method_not_allowed", "only GET is allowed")
		return
	}
	if err := s.store.Ready(); err != nil {
		log.Printf("sync store is not ready: %v", err)
		writeJSON(response, http.StatusServiceUnavailable, map[string]string{"status": "unavailable"})
		return
	}
	writeJSON(response, http.StatusOK, map[string]string{"status": "ok"})
}

type syncRequest struct {
	DeviceID string            `json:"deviceId"`
	Tasks    []json.RawMessage `json:"tasks"`
	Pomodoro json.RawMessage   `json:"pomodoro,omitempty"`
}

type syncResponse struct {
	Tasks      []json.RawMessage `json:"tasks"`
	Pomodoro   json.RawMessage   `json:"pomodoro,omitempty"`
	ServerTime string            `json:"serverTime"`
}

func (s *Server) sync(response http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost {
		response.Header().Set("Allow", http.MethodPost)
		writeError(response, http.StatusMethodNotAllowed, "method_not_allowed", "only POST is allowed")
		return
	}
	if !s.requireAuthorization(response, request) {
		return
	}

	request.Body = http.MaxBytesReader(response, request.Body, s.maxBodyBytes)
	defer request.Body.Close()
	decoder := json.NewDecoder(request.Body)
	decoder.DisallowUnknownFields()
	var input syncRequest
	if err := decoder.Decode(&input); err != nil {
		s.writeDecodeError(response, err)
		return
	}
	if err := requireEOF(decoder); err != nil {
		s.writeDecodeError(response, err)
		return
	}

	input.DeviceID = strings.TrimSpace(input.DeviceID)
	if input.DeviceID == "" || len(input.DeviceID) > 128 {
		writeError(response, http.StatusBadRequest, "invalid_device_id", "deviceId must contain 1 to 128 characters")
		return
	}
	if len(input.Tasks) > maxTasksPerRequest {
		writeError(response, http.StatusBadRequest, "too_many_tasks", fmt.Sprintf("at most %d tasks are allowed", maxTasksPerRequest))
		return
	}

	tasks := make([]store.Task, 0, len(input.Tasks))
	latestAllowedUpdate := time.Now().UTC().Add(maxFutureClockSkew)
	for index, raw := range input.Tasks {
		task, err := store.ParseTask(raw)
		if err != nil {
			writeError(response, http.StatusBadRequest, "invalid_task", fmt.Sprintf("tasks[%d]: %v", index, err))
			return
		}
		if task.UpdatedAt.After(latestAllowedUpdate) {
			writeError(response, http.StatusBadRequest, "future_updated_at", fmt.Sprintf("tasks[%d].updatedAt is more than 5 minutes in the future", index))
			return
		}
		tasks = append(tasks, task)
	}
	var pomodoro *store.Pomodoro
	if len(input.Pomodoro) > 0 && string(input.Pomodoro) != "null" {
		parsed, err := store.ParsePomodoro(input.Pomodoro)
		if err != nil {
			writeError(response, http.StatusBadRequest, "invalid_pomodoro", err.Error())
			return
		}
		if parsed.UpdatedAt.After(latestAllowedUpdate) {
			writeError(response, http.StatusBadRequest, "future_updated_at", "pomodoro.updatedAt is more than 5 minutes in the future")
			return
		}
		pomodoro = &parsed
	}

	merged, mergedPomodoro, err := s.store.MergeAll(tasks, pomodoro)
	if err != nil {
		log.Printf("persist sync data: %v", err)
		if errors.Is(err, store.ErrCapacityExceeded) {
			writeError(response, http.StatusInsufficientStorage, "store_capacity_exceeded", "sync store task or data limit reached")
			return
		}
		writeError(response, http.StatusInternalServerError, "storage_error", "could not persist sync data")
		return
	}
	writeJSON(response, http.StatusOK, syncResponse{
		Tasks:      merged,
		Pomodoro:   mergedPomodoro,
		ServerTime: time.Now().UTC().Format(time.RFC3339Nano),
	})
}

func (s *Server) authorized(value string) bool {
	scheme, token, found := strings.Cut(strings.TrimSpace(value), " ")
	if !found || !strings.EqualFold(scheme, "Bearer") || token == "" {
		return false
	}
	presentedHash := sha256.Sum256([]byte(token))
	return subtle.ConstantTimeCompare(presentedHash[:], s.tokenHash[:]) == 1
}

func (s *Server) requireAuthorization(response http.ResponseWriter, request *http.Request) bool {
	if s.authorized(request.Header.Get("Authorization")) {
		return true
	}
	response.Header().Set("WWW-Authenticate", `Bearer realm="qingxu-sync"`)
	writeError(response, http.StatusUnauthorized, "unauthorized", "a valid bearer token is required")
	return false
}

func (s *Server) writeDecodeError(response http.ResponseWriter, err error) {
	var tooLarge *http.MaxBytesError
	if errors.As(err, &tooLarge) {
		writeError(response, http.StatusRequestEntityTooLarge, "request_too_large", fmt.Sprintf("request body exceeds %d bytes", s.maxBodyBytes))
		return
	}
	writeError(response, http.StatusBadRequest, "invalid_json", "request body must be one valid JSON object")
}

func (s *Server) withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		origin := request.Header.Get("Origin")
		if origin != "" {
			response.Header().Add("Vary", "Origin")
			if !s.originAllowed(origin) {
				writeError(response, http.StatusForbidden, "origin_not_allowed", "request origin is not allowed")
				return
			}
			if s.allowAny {
				response.Header().Set("Access-Control-Allow-Origin", "*")
			} else {
				response.Header().Set("Access-Control-Allow-Origin", origin)
			}
		}
		if request.Method == http.MethodOptions {
			if origin == "" {
				writeError(response, http.StatusBadRequest, "missing_origin", "preflight request requires Origin")
				return
			}
			response.Header().Add("Vary", "Access-Control-Request-Method")
			response.Header().Add("Vary", "Access-Control-Request-Headers")
			expectedMethod := ""
			switch request.URL.Path {
			case "/v1/sync":
				expectedMethod = http.MethodPost
			case "/v1/ping":
				expectedMethod = http.MethodGet
			default:
				writeError(response, http.StatusNotFound, "not_found", "preflight path is not available")
				return
			}
			if request.Header.Get("Access-Control-Request-Method") != expectedMethod {
				writeError(response, http.StatusMethodNotAllowed, "method_not_allowed", "preflight method must be "+expectedMethod)
				return
			}
			if unsupported := unsupportedCORSHeader(request.Header.Get("Access-Control-Request-Headers")); unsupported != "" {
				writeError(response, http.StatusForbidden, "header_not_allowed", "preflight header is not allowed: "+unsupported)
				return
			}
			response.Header().Set("Access-Control-Allow-Methods", expectedMethod)
			response.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			response.Header().Set("Access-Control-Max-Age", "600")
			response.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(response, request)
	})
}

func unsupportedCORSHeader(value string) string {
	for _, part := range strings.Split(value, ",") {
		header := strings.TrimSpace(part)
		if header == "" || strings.EqualFold(header, "Authorization") || strings.EqualFold(header, "Content-Type") {
			continue
		}
		return header
	}
	return ""
}

func (s *Server) originAllowed(origin string) bool {
	if s.allowAny {
		return true
	}
	_, allowed := s.origins[origin]
	return allowed
}

func writeJSON(response http.ResponseWriter, status int, value any) {
	response.Header().Set("Content-Type", "application/json; charset=utf-8")
	response.Header().Set("Cache-Control", "no-store")
	response.Header().Set("X-Content-Type-Options", "nosniff")
	response.WriteHeader(status)
	_ = json.NewEncoder(response).Encode(value)
}

func writeError(response http.ResponseWriter, status int, code, message string) {
	writeJSON(response, status, map[string]any{
		"error": map[string]string{
			"code":    code,
			"message": message,
		},
	})
}

func requireEOF(decoder *json.Decoder) error {
	var extra any
	err := decoder.Decode(&extra)
	if errors.Is(err, io.EOF) {
		return nil
	}
	if err == nil {
		return errors.New("multiple JSON values are not allowed")
	}
	return err
}
