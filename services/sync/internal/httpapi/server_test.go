package httpapi

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/FelixZoe/qingxu/services/sync/internal/store"
)

const testToken = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

func TestBuildAIPromptAcceptsTranslationSegments(t *testing.T) {
	system, prompt, err := buildAIPrompt(aiInput{
		Mode:    "rss_translation",
		Content: `["A short title","A longer paragraph."]`,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(system, "JSON") || !strings.Contains(prompt, "A short title") {
		t.Fatalf("unexpected translation prompt: system=%q prompt=%q", system, prompt)
	}
}

func TestBuildAIPromptRejectsInvalidTranslationPayload(t *testing.T) {
	if _, _, err := buildAIPrompt(aiInput{Mode: "rss_translation", Content: `not-json`}); err == nil {
		t.Fatal("expected invalid translation payload to be rejected")
	}
}

func TestNewRejectsNonHexOrWeakToken(t *testing.T) {
	taskStore, err := store.Open(filepath.Join(t.TempDir(), "store.json"))
	if err != nil {
		t.Fatal(err)
	}
	for _, token := range []string{"short", strings.Repeat("z", 64), "replace-with-a-long-random-token"} {
		if _, err := New(Config{Token: token, MaxBodyBytes: 2048}, taskStore); err == nil {
			t.Fatalf("New() accepted invalid token %q", token)
		}
	}
}

func TestHealthDoesNotRequireAuthentication(t *testing.T) {
	handler := newTestHandler(t, Config{Token: testToken, MaxBodyBytes: 2048})
	request := httptest.NewRequest(http.MethodGet, "/health", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body)
	}
}

func TestSyncRequiresBearerToken(t *testing.T) {
	handler := newTestHandler(t, Config{Token: testToken, MaxBodyBytes: 2048})
	request := httptest.NewRequest(http.MethodPost, "/v1/sync", strings.NewReader(`{"deviceId":"ios","tasks":[]}`))
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body)
	}
}

func TestPingTestsTokenWithoutReturningTasks(t *testing.T) {
	handler := newTestHandler(t, Config{Token: testToken, MaxBodyBytes: 2048})

	unauthorized := httptest.NewRequest(http.MethodGet, "/v1/ping", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, unauthorized)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized status = %d", response.Code)
	}

	authorized := httptest.NewRequest(http.MethodGet, "/v1/ping", nil)
	authorized.Header.Set("Authorization", "Bearer "+testToken)
	response = httptest.NewRecorder()
	handler.ServeHTTP(response, authorized)
	if response.Code != http.StatusOK || strings.TrimSpace(response.Body.String()) != `{"status":"ok"}` {
		t.Fatalf("ping status = %d, body = %s", response.Code, response.Body)
	}
}

func TestSyncMergesAndReturnsCompleteTaskDocuments(t *testing.T) {
	handler := newTestHandler(t, Config{Token: testToken, MaxBodyBytes: 4096})

	first := syncRequestBody("windows", `{
      "id":"task-1","title":"server wins","notes":"kept","status":"open",
      "order":0,"createdAt":"2024-08-22T09:00:00Z",
      "updatedAt":"2024-08-22T11:00:00Z","deletedAt":"2024-08-22T11:00:00Z"
    }`)
	response := performSync(handler, first)
	if response.Code != http.StatusOK {
		t.Fatalf("first sync status = %d, body = %s", response.Code, response.Body)
	}

	stale := syncRequestBody("ios", `{
      "id":"task-1","title":"stale","notes":"","status":"open",
      "order":0,"createdAt":"2024-08-22T09:00:00Z",
      "updatedAt":"2024-08-22T10:00:00Z","deletedAt":null
    }`)
	response = performSync(handler, stale)
	if response.Code != http.StatusOK {
		t.Fatalf("second sync status = %d, body = %s", response.Code, response.Body)
	}

	var output struct {
		Tasks      []map[string]any `json:"tasks"`
		ServerTime string           `json:"serverTime"`
		Revision   uint64           `json:"revision"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &output); err != nil {
		t.Fatal(err)
	}
	if len(output.Tasks) != 1 || output.Tasks[0]["title"] != "server wins" {
		t.Fatalf("unexpected merged tasks: %#v", output.Tasks)
	}
	if output.Tasks[0]["deletedAt"] != "2024-08-22T11:00:00Z" {
		t.Fatalf("tombstone missing: %#v", output.Tasks[0])
	}
	if output.ServerTime == "" {
		t.Fatal("serverTime is empty")
	}
	if output.Revision == 0 {
		t.Fatal("revision is empty")
	}
}

func TestChangesRequiresAuthenticationAndReturnsCurrentRevision(t *testing.T) {
	handler := newTestHandler(t, Config{Token: testToken, MaxBodyBytes: 2048})
	request := httptest.NewRequest(http.MethodGet, "/v1/changes?since=0", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized status = %d", response.Code)
	}

	request = httptest.NewRequest(http.MethodGet, "/v1/changes?since=0", nil)
	request.Header.Set("Authorization", "Bearer "+testToken)
	response = httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body)
	}
	var output changesResponse
	if err := json.Unmarshal(response.Body.Bytes(), &output); err != nil {
		t.Fatal(err)
	}
	if !output.Changed || output.Revision == 0 {
		t.Fatalf("unexpected changes response: %#v", output)
	}
}

func TestSyncRejectsOversizedBody(t *testing.T) {
	handler := newTestHandler(t, Config{Token: testToken, MaxBodyBytes: 64})
	body := `{"deviceId":"ios","tasks":[],"padding":"` + strings.Repeat("x", 100) + `"}`
	response := performSync(handler, []byte(body))
	if response.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body)
	}
}

func TestSyncRejectsUpdatedAtTooFarInFuture(t *testing.T) {
	handler := newTestHandler(t, Config{Token: testToken, MaxBodyBytes: 2048})
	future := time.Now().UTC().Add(10 * time.Minute).Format(time.RFC3339Nano)
	body := syncRequestBody("ios", `{
      "id":"future","title":"future","updatedAt":`+quoted(future)+`,"deletedAt":null
    }`)
	response := performSync(handler, body)
	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body)
	}
	if !strings.Contains(response.Body.String(), "future_updated_at") {
		t.Fatalf("unexpected body = %s", response.Body)
	}
}

func TestCORSAllowsConfiguredOriginAndRejectsOthers(t *testing.T) {
	handler := newTestHandler(t, Config{
		Token:          testToken,
		MaxBodyBytes:   2048,
		AllowedOrigins: []string{"https://tasks.example.com"},
	})

	preflight := httptest.NewRequest(http.MethodOptions, "/v1/sync", nil)
	preflight.Header.Set("Origin", "https://tasks.example.com")
	preflight.Header.Set("Access-Control-Request-Method", http.MethodPost)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, preflight)
	if response.Code != http.StatusNoContent {
		t.Fatalf("preflight status = %d", response.Code)
	}
	if got := response.Header().Get("Access-Control-Allow-Origin"); got != "https://tasks.example.com" {
		t.Fatalf("allow origin = %q", got)
	}
	if got := response.Header().Values("Vary"); len(got) < 3 {
		t.Fatalf("preflight Vary headers = %v", got)
	}

	badHeader := httptest.NewRequest(http.MethodOptions, "/v1/sync", nil)
	badHeader.Header.Set("Origin", "https://tasks.example.com")
	badHeader.Header.Set("Access-Control-Request-Method", http.MethodPost)
	badHeader.Header.Set("Access-Control-Request-Headers", "X-Unsafe-Header")
	response = httptest.NewRecorder()
	handler.ServeHTTP(response, badHeader)
	if response.Code != http.StatusForbidden {
		t.Fatalf("unsupported preflight header status = %d", response.Code)
	}

	pingPreflight := httptest.NewRequest(http.MethodOptions, "/v1/ping", nil)
	pingPreflight.Header.Set("Origin", "https://tasks.example.com")
	pingPreflight.Header.Set("Access-Control-Request-Method", http.MethodGet)
	pingPreflight.Header.Set("Access-Control-Request-Headers", "Authorization")
	response = httptest.NewRecorder()
	handler.ServeHTTP(response, pingPreflight)
	if response.Code != http.StatusNoContent || response.Header().Get("Access-Control-Allow-Methods") != http.MethodGet {
		t.Fatalf("ping preflight status = %d, headers = %v", response.Code, response.Header())
	}

	blocked := httptest.NewRequest(http.MethodGet, "/health", nil)
	blocked.Header.Set("Origin", "https://evil.example")
	response = httptest.NewRecorder()
	handler.ServeHTTP(response, blocked)
	if response.Code != http.StatusForbidden {
		t.Fatalf("blocked origin status = %d", response.Code)
	}
}

func newTestHandler(t *testing.T, config Config) http.Handler {
	t.Helper()
	taskStore, err := store.Open(filepath.Join(t.TempDir(), "store.json"))
	if err != nil {
		t.Fatal(err)
	}
	server, err := New(config, taskStore)
	if err != nil {
		t.Fatal(err)
	}
	return server.Handler()
}

func syncRequestBody(deviceID, task string) []byte {
	return []byte(`{"deviceId":` + quoted(deviceID) + `,"tasks":[` + task + `]}`)
}

func quoted(value string) string {
	encoded, _ := json.Marshal(value)
	return string(encoded)
}

func performSync(handler http.Handler, body []byte) *httptest.ResponseRecorder {
	request := httptest.NewRequest(http.MethodPost, "/v1/sync", bytes.NewReader(body))
	request.Header.Set("Authorization", "Bearer "+testToken)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	return response
}
