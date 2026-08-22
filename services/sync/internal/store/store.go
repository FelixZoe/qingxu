package store

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	diskFormatVersion = 2
	oldestDiskVersion = 1
	maxStoredTasks    = 20_000
	maxStoredJSONSize = 8 << 20
	maxDiskFileSize   = 10 << 20
	readinessCacheTTL = 10 * time.Second
)

var ErrCapacityExceeded = errors.New("sync store capacity exceeded")

// Task keeps the complete client JSON document so adding TaskItem fields does
// not require a server migration. Only the sync metadata is interpreted here.
type Task struct {
	ID        string
	UpdatedAt time.Time
	DeletedAt *time.Time
	JSON      json.RawMessage
}

type taskMetadata struct {
	ID        string  `json:"id"`
	UpdatedAt string  `json:"updatedAt"`
	DeletedAt *string `json:"deletedAt"`
}

// Pomodoro keeps the complete timer document and uses the same last-write-wins
// rule as tasks. It is a singleton because one account has one active timer.
type Pomodoro struct {
	UpdatedAt time.Time
	JSON      json.RawMessage
}

type pomodoroMetadata struct {
	UpdatedAt string `json:"updatedAt"`
}

func ParsePomodoro(raw json.RawMessage) (Pomodoro, error) {
	trimmed := bytes.TrimSpace(raw)
	if len(trimmed) == 0 || trimmed[0] != '{' {
		return Pomodoro{}, errors.New("pomodoro must be a JSON object")
	}
	var metadata pomodoroMetadata
	if err := json.Unmarshal(trimmed, &metadata); err != nil {
		return Pomodoro{}, fmt.Errorf("decode pomodoro: %w", err)
	}
	updatedAt, err := time.Parse(time.RFC3339Nano, metadata.UpdatedAt)
	if err != nil {
		return Pomodoro{}, fmt.Errorf("invalid pomodoro updatedAt: %w", err)
	}
	return Pomodoro{
		UpdatedAt: updatedAt.UTC(),
		JSON:      append(json.RawMessage(nil), trimmed...),
	}, nil
}

// ParseTask validates the fields needed by the merge algorithm while retaining
// all of the original TaskItem fields.
func ParseTask(raw json.RawMessage) (Task, error) {
	trimmed := bytes.TrimSpace(raw)
	if len(trimmed) == 0 || trimmed[0] != '{' {
		return Task{}, errors.New("task must be a JSON object")
	}

	var metadata taskMetadata
	if err := json.Unmarshal(trimmed, &metadata); err != nil {
		return Task{}, fmt.Errorf("decode task: %w", err)
	}
	if strings.TrimSpace(metadata.ID) == "" {
		return Task{}, errors.New("task id is required")
	}
	if len(metadata.ID) > 256 {
		return Task{}, errors.New("task id is too long")
	}
	if metadata.UpdatedAt == "" {
		return Task{}, errors.New("task updatedAt is required")
	}
	updatedAt, err := time.Parse(time.RFC3339Nano, metadata.UpdatedAt)
	if err != nil {
		return Task{}, fmt.Errorf("invalid task updatedAt: %w", err)
	}

	var deletedAt *time.Time
	if metadata.DeletedAt != nil {
		parsed, err := time.Parse(time.RFC3339Nano, *metadata.DeletedAt)
		if err != nil {
			return Task{}, fmt.Errorf("invalid task deletedAt: %w", err)
		}
		if parsed.After(updatedAt) {
			return Task{}, errors.New("task deletedAt must not be later than updatedAt")
		}
		deletedAt = &parsed
	}

	return Task{
		ID:        metadata.ID,
		UpdatedAt: updatedAt.UTC(),
		DeletedAt: deletedAt,
		JSON:      append(json.RawMessage(nil), trimmed...),
	}, nil
}

type diskState struct {
	Version  int               `json:"version"`
	Tasks    []json.RawMessage `json:"tasks"`
	Pomodoro json.RawMessage   `json:"pomodoro,omitempty"`
}

// Store serializes merges so the file and the in-memory snapshot always move
// forward together.
type Store struct {
	mu                 sync.Mutex
	path               string
	tasks              map[string]Task
	pomodoro           *Pomodoro
	needsDirectorySync bool
	readinessMu        sync.Mutex
	readinessCheckedAt time.Time
	readinessErr       error
}

func Open(path string) (*Store, error) {
	if strings.TrimSpace(path) == "" {
		return nil, errors.New("data file path is required")
	}
	s := &Store{path: filepath.Clean(path), tasks: make(map[string]Task)}
	if err := ensureWritableDirectory(filepath.Dir(s.path)); err != nil {
		return nil, err
	}
	s.markReadiness(nil)
	if err := s.load(); err != nil {
		return nil, err
	}
	return s, nil
}

func ensureWritableDirectory(directory string) error {
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return fmt.Errorf("create data directory: %w", err)
	}
	probe, err := os.CreateTemp(directory, ".write-probe-*")
	if err != nil {
		return fmt.Errorf("data directory is not writable: %w", err)
	}
	probePath := probe.Name()
	if _, err := probe.Write([]byte{0}); err != nil {
		probe.Close()
		os.Remove(probePath)
		return fmt.Errorf("write data directory probe: %w", err)
	}
	if err := probe.Sync(); err != nil {
		probe.Close()
		os.Remove(probePath)
		return fmt.Errorf("sync data directory probe: %w", err)
	}
	if err := probe.Close(); err != nil {
		os.Remove(probePath)
		return fmt.Errorf("close data directory probe: %w", err)
	}
	if err := os.Remove(probePath); err != nil {
		return fmt.Errorf("remove data directory probe: %w", err)
	}
	return nil
}

// Ready verifies that the persistence directory is still writable. It is used
// by the health endpoint so a full or detached data volume is not reported as
// healthy merely because the HTTP listener is alive.
func (s *Store) Ready() error {
	s.mu.Lock()
	if s.needsDirectorySync {
		err := syncDirectory(filepath.Dir(s.path))
		if err == nil {
			s.needsDirectorySync = false
		}
		s.markReadiness(err)
		s.mu.Unlock()
		return err
	}
	s.mu.Unlock()

	s.readinessMu.Lock()
	defer s.readinessMu.Unlock()
	if !s.readinessCheckedAt.IsZero() {
		elapsed := time.Since(s.readinessCheckedAt)
		if elapsed >= 0 && elapsed < readinessCacheTTL {
			return s.readinessErr
		}
	}
	s.readinessErr = ensureWritableDirectory(filepath.Dir(s.path))
	s.readinessCheckedAt = time.Now()
	return s.readinessErr
}

func (s *Store) markReadiness(err error) {
	s.readinessMu.Lock()
	s.readinessErr = err
	s.readinessCheckedAt = time.Now()
	s.readinessMu.Unlock()
}

func (s *Store) load() error {
	file, err := os.Open(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("open data file: %w", err)
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return fmt.Errorf("stat data file: %w", err)
	}
	if info.Size() > maxDiskFileSize {
		return fmt.Errorf("data file exceeds %d bytes", maxDiskFileSize)
	}

	decoder := json.NewDecoder(file)
	decoder.DisallowUnknownFields()
	var state diskState
	if err := decoder.Decode(&state); err != nil {
		return fmt.Errorf("decode data file: %w", err)
	}
	if err := requireEOF(decoder); err != nil {
		return fmt.Errorf("decode data file: %w", err)
	}
	if state.Version < oldestDiskVersion || state.Version > diskFormatVersion {
		return fmt.Errorf("unsupported data format version %d", state.Version)
	}

	for index, raw := range state.Tasks {
		task, err := ParseTask(raw)
		if err != nil {
			return fmt.Errorf("invalid stored task %d: %w", index, err)
		}
		current, exists := s.tasks[task.ID]
		if !exists || shouldReplace(current, task) {
			s.tasks[task.ID] = task
		}
	}
	if len(bytes.TrimSpace(state.Pomodoro)) > 0 {
		pomodoro, err := ParsePomodoro(state.Pomodoro)
		if err != nil {
			return fmt.Errorf("invalid stored pomodoro: %w", err)
		}
		s.pomodoro = &pomodoro
	}
	if err := validateCapacity(s.tasks); err != nil {
		return err
	}
	return nil
}

// Merge applies last-write-wins by updatedAt. Equal timestamps retain the
// server copy except that a tombstone wins over a live task. Deleted tasks are
// deliberately kept in the returned and persisted collection.
func (s *Store) Merge(incoming []Task) ([]json.RawMessage, error) {
	tasks, _, err := s.MergeAll(incoming, nil)
	return tasks, err
}

// MergeAll atomically merges all user data represented by the sync protocol.
func (s *Store) MergeAll(incoming []Task, incomingPomodoro *Pomodoro) ([]json.RawMessage, json.RawMessage, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.needsDirectorySync {
		if err := syncDirectory(filepath.Dir(s.path)); err != nil {
			s.markReadiness(err)
			return nil, nil, fmt.Errorf("sync data directory: %w", err)
		}
		s.needsDirectorySync = false
		s.markReadiness(nil)
	}

	next := cloneTasks(s.tasks)
	nextPomodoro := s.pomodoro
	changed := false
	for _, task := range incoming {
		current, exists := next[task.ID]
		if !exists || shouldReplace(current, task) {
			next[task.ID] = task
			changed = true
		}
	}
	if incomingPomodoro != nil &&
		(nextPomodoro == nil || incomingPomodoro.UpdatedAt.After(nextPomodoro.UpdatedAt)) {
		copy := *incomingPomodoro
		nextPomodoro = &copy
		changed = true
	}

	if changed {
		if err := validateCapacity(next); err != nil {
			return nil, nil, err
		}
		replaced, err := writeStateAtomic(s.path, next, nextPomodoro)
		if replaced {
			s.tasks = next
			s.pomodoro = nextPomodoro
		}
		if err != nil {
			s.needsDirectorySync = replaced
			s.markReadiness(err)
			return nil, nil, err
		}
		s.markReadiness(nil)
	}
	var pomodoroJSON json.RawMessage
	if nextPomodoro != nil {
		pomodoroJSON = append(json.RawMessage(nil), nextPomodoro.JSON...)
	}
	return snapshot(next), pomodoroJSON, nil
}

func shouldReplace(current, incoming Task) bool {
	if incoming.UpdatedAt.After(current.UpdatedAt) {
		return true
	}
	if !incoming.UpdatedAt.Equal(current.UpdatedAt) {
		return false
	}
	// A delete and an edit can share the same client clock tick. Giving the
	// tombstone priority prevents an equal-time live copy from resurrecting it.
	return current.DeletedAt == nil && incoming.DeletedAt != nil
}

func validateCapacity(tasks map[string]Task) error {
	if len(tasks) > maxStoredTasks {
		return fmt.Errorf("%w: at most %d tasks are allowed", ErrCapacityExceeded, maxStoredTasks)
	}
	total := 0
	for _, task := range tasks {
		total += len(task.JSON)
		if total > maxStoredJSONSize {
			return fmt.Errorf("%w: task JSON exceeds %d bytes", ErrCapacityExceeded, maxStoredJSONSize)
		}
	}
	return nil
}

func cloneTasks(source map[string]Task) map[string]Task {
	result := make(map[string]Task, len(source))
	for id, task := range source {
		result[id] = task
	}
	return result
}

func snapshot(tasks map[string]Task) []json.RawMessage {
	ids := make([]string, 0, len(tasks))
	for id := range tasks {
		ids = append(ids, id)
	}
	sort.Strings(ids)

	result := make([]json.RawMessage, 0, len(ids))
	for _, id := range ids {
		result = append(result, append(json.RawMessage(nil), tasks[id].JSON...))
	}
	return result
}

func writeStateAtomic(path string, tasks map[string]Task, pomodoro *Pomodoro) (bool, error) {
	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return false, fmt.Errorf("create data directory: %w", err)
	}

	var pomodoroJSON json.RawMessage
	if pomodoro != nil {
		pomodoroJSON = pomodoro.JSON
	}
	payload, err := json.Marshal(diskState{
		Version:  diskFormatVersion,
		Tasks:    snapshot(tasks),
		Pomodoro: pomodoroJSON,
	})
	if err != nil {
		return false, fmt.Errorf("encode data file: %w", err)
	}
	payload = append(payload, '\n')
	if len(payload) > maxDiskFileSize {
		return false, fmt.Errorf("%w: encoded data file exceeds %d bytes", ErrCapacityExceeded, maxDiskFileSize)
	}

	temporary, err := os.CreateTemp(directory, "."+filepath.Base(path)+".tmp-*")
	if err != nil {
		return false, fmt.Errorf("create temporary data file: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)

	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return false, fmt.Errorf("secure temporary data file: %w", err)
	}
	if _, err := temporary.Write(payload); err != nil {
		temporary.Close()
		return false, fmt.Errorf("write temporary data file: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return false, fmt.Errorf("sync temporary data file: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return false, fmt.Errorf("close temporary data file: %w", err)
	}
	if err := replaceFile(temporaryPath, path); err != nil {
		return false, fmt.Errorf("replace data file: %w", err)
	}
	if err := syncDirectory(directory); err != nil {
		return true, fmt.Errorf("sync data directory: %w", err)
	}
	return true, nil
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
