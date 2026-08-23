package store

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestMergeUsesUpdatedAtAndPersistsTombstone(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nested", "store.json")
	taskStore, err := Open(path)
	if err != nil {
		t.Fatalf("Open() error = %v", err)
	}

	live := mustTask(t, `{
      "id":"task-1","title":"new title","updatedAt":"2026-08-22T10:00:00Z","deletedAt":null
    }`)
	merged, err := taskStore.Merge([]Task{live})
	if err != nil {
		t.Fatalf("Merge(live) error = %v", err)
	}
	if len(merged) != 1 || titleOf(t, merged[0]) != "new title" {
		t.Fatalf("Merge(live) = %v", merged)
	}

	stale := mustTask(t, `{
      "id":"task-1","title":"stale title","updatedAt":"2026-08-22T09:00:00Z","deletedAt":null
    }`)
	merged, err = taskStore.Merge([]Task{stale})
	if err != nil {
		t.Fatalf("Merge(stale) error = %v", err)
	}
	if got := titleOf(t, merged[0]); got != "new title" {
		t.Fatalf("stale update won; title = %q", got)
	}

	tombstone := mustTask(t, `{
      "id":"task-1","title":"new title","updatedAt":"2026-08-22T11:00:00Z","deletedAt":"2026-08-22T11:00:00Z"
    }`)
	if _, err := taskStore.Merge([]Task{tombstone}); err != nil {
		t.Fatalf("Merge(tombstone) error = %v", err)
	}

	reopened, err := Open(path)
	if err != nil {
		t.Fatalf("Open(persisted) error = %v", err)
	}
	merged, err = reopened.Merge([]Task{stale})
	if err != nil {
		t.Fatalf("Merge(after reopen) error = %v", err)
	}
	if len(merged) != 1 {
		t.Fatalf("persisted task count = %d", len(merged))
	}
	var fields map[string]any
	if err := json.Unmarshal(merged[0], &fields); err != nil {
		t.Fatal(err)
	}
	if fields["deletedAt"] != "2026-08-22T11:00:00Z" {
		t.Fatalf("deletedAt tombstone was lost: %s", merged[0])
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("persisted file error = %v", err)
	}
}

func TestEqualTimestampKeepsServerCopy(t *testing.T) {
	taskStore, err := Open(filepath.Join(t.TempDir(), "store.json"))
	if err != nil {
		t.Fatal(err)
	}
	first := mustTask(t, `{"id":"same","title":"first","updatedAt":"2026-08-22T10:00:00Z","deletedAt":null}`)
	second := mustTask(t, `{"id":"same","title":"second","updatedAt":"2026-08-22T10:00:00Z","deletedAt":null}`)
	if _, err := taskStore.Merge([]Task{first}); err != nil {
		t.Fatal(err)
	}
	merged, err := taskStore.Merge([]Task{second})
	if err != nil {
		t.Fatal(err)
	}
	if got := titleOf(t, merged[0]); got != "first" {
		t.Fatalf("equal timestamp changed server copy to %q", got)
	}
}

func TestEqualTimestampTombstoneWins(t *testing.T) {
	taskStore, err := Open(filepath.Join(t.TempDir(), "store.json"))
	if err != nil {
		t.Fatal(err)
	}
	live := mustTask(t, `{"id":"same","title":"live","updatedAt":"2026-08-22T10:00:00Z","deletedAt":null}`)
	tombstone := mustTask(t, `{"id":"same","title":"live","updatedAt":"2026-08-22T10:00:00Z","deletedAt":"2026-08-22T10:00:00Z"}`)
	if _, err := taskStore.Merge([]Task{live}); err != nil {
		t.Fatal(err)
	}
	merged, err := taskStore.Merge([]Task{tombstone})
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]any
	if err := json.Unmarshal(merged[0], &fields); err != nil {
		t.Fatal(err)
	}
	if fields["deletedAt"] == nil {
		t.Fatalf("equal-time tombstone did not win: %s", merged[0])
	}
}

func TestParseTaskRejectsDeletedAtAfterUpdatedAt(t *testing.T) {
	_, err := ParseTask(json.RawMessage(`{
      "id":"task-1","updatedAt":"2026-08-22T10:00:00Z","deletedAt":"2026-08-22T10:00:01Z"
    }`))
	if err == nil {
		t.Fatal("ParseTask() accepted deletedAt later than updatedAt")
	}
}

func TestPomodoroMergePersistsNewestState(t *testing.T) {
	path := filepath.Join(t.TempDir(), "store.json")
	taskStore, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	first, err := ParsePomodoro(json.RawMessage(`{"mode":"focus","status":"running","updatedAt":"2026-08-22T10:00:00Z"}`))
	if err != nil {
		t.Fatal(err)
	}
	_, merged, _, err := taskStore.MergeAll(nil, &first)
	if err != nil || !strings.Contains(string(merged), `"status":"running"`) {
		t.Fatalf("MergeAll(first) = %s, %v", merged, err)
	}

	stale, err := ParsePomodoro(json.RawMessage(`{"mode":"focus","status":"paused","updatedAt":"2026-08-22T09:00:00Z"}`))
	if err != nil {
		t.Fatal(err)
	}
	_, merged, _, err = taskStore.MergeAll(nil, &stale)
	if err != nil || !strings.Contains(string(merged), `"status":"running"`) {
		t.Fatalf("stale pomodoro won: %s, %v", merged, err)
	}

	reopened, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	_, merged, _, err = reopened.MergeAll(nil, nil)
	if err != nil || !strings.Contains(string(merged), `"status":"running"`) {
		t.Fatalf("persisted pomodoro lost: %s, %v", merged, err)
	}
}

func TestWaitForChangeWakesAfterMerge(t *testing.T) {
	taskStore, err := Open(filepath.Join(t.TempDir(), "store.json"))
	if err != nil {
		t.Fatal(err)
	}
	before := taskStore.Revision()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	woke := make(chan uint64, 1)
	go func() { woke <- taskStore.WaitForChange(ctx, before) }()

	task := mustTask(t, `{"id":"wake","title":"wake","updatedAt":"2026-08-23T08:00:00Z","deletedAt":null}`)
	if _, err := taskStore.Merge([]Task{task}); err != nil {
		t.Fatal(err)
	}
	select {
	case revision := <-woke:
		if revision <= before {
			t.Fatalf("revision did not advance: before=%d after=%d", before, revision)
		}
	case <-time.After(time.Second):
		t.Fatal("WaitForChange did not wake after merge")
	}
}

func TestCapacityLimitsTaskCountAndJSONSize(t *testing.T) {
	tasks := make(map[string]Task, maxStoredTasks+1)
	for index := 0; index <= maxStoredTasks; index++ {
		id := strconv.Itoa(index)
		tasks[id] = Task{JSON: json.RawMessage(`{}`)}
	}
	if err := validateCapacity(tasks); !errors.Is(err, ErrCapacityExceeded) {
		t.Fatalf("task count error = %v", err)
	}

	tasks = map[string]Task{
		"large": {JSON: json.RawMessage(strings.Repeat("x", maxStoredJSONSize+1))},
	}
	if err := validateCapacity(tasks); !errors.Is(err, ErrCapacityExceeded) {
		t.Fatalf("JSON size error = %v", err)
	}
}

func TestOpenRejectsCorruptData(t *testing.T) {
	path := filepath.Join(t.TempDir(), "store.json")
	if err := os.WriteFile(path, []byte(`{"version":1,"tasks":[{"id":"missing-time"}]}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Open(path); err == nil {
		t.Fatal("Open() accepted invalid stored task")
	}
}

func mustTask(t *testing.T, raw string) Task {
	t.Helper()
	task, err := ParseTask(json.RawMessage(raw))
	if err != nil {
		t.Fatalf("ParseTask() error = %v", err)
	}
	return task
}

func titleOf(t *testing.T, raw json.RawMessage) string {
	t.Helper()
	var fields struct {
		Title string `json:"title"`
	}
	if err := json.Unmarshal(raw, &fields); err != nil {
		t.Fatalf("decode task title: %v", err)
	}
	return fields.Title
}
