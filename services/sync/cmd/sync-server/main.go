package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/FelixZoe/qingxu/services/sync/internal/httpapi"
	"github.com/FelixZoe/qingxu/services/sync/internal/store"
)

const defaultMaxBodyBytes int64 = 2 << 20

func main() {
	if len(os.Args) == 2 && os.Args[1] == "healthcheck" {
		if err := healthcheck(); err != nil {
			log.Print(err)
			os.Exit(1)
		}
		return
	}
	if err := run(); err != nil {
		log.Fatal(err)
	}
}

func run() error {
	config, err := loadConfig()
	if err != nil {
		return err
	}
	taskStore, err := store.Open(config.dataFile)
	if err != nil {
		return fmt.Errorf("open sync store: %w", err)
	}
	api, err := httpapi.New(httpapi.Config{
		Token:          config.token,
		AllowedOrigins: config.allowedOrigins,
		MaxBodyBytes:   config.maxBodyBytes,
		AIBaseURL:      config.aiBaseURL,
		AIAPIKey:       config.aiAPIKey,
		AIModel:        config.aiModel,
	}, taskStore)
	if err != nil {
		return fmt.Errorf("configure API: %w", err)
	}

	server := &http.Server{
		Addr:              config.address,
		Handler:           api.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    32 << 10,
	}

	serverErrors := make(chan error, 1)
	go func() {
		log.Printf("qingxu sync listening on %s", config.address)
		serverErrors <- server.ListenAndServe()
	}()

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	select {
	case signalValue := <-signals:
		log.Printf("received %s; shutting down", signalValue)
	case err := <-serverErrors:
		if !errors.Is(err, http.ErrServerClosed) {
			return fmt.Errorf("serve: %w", err)
		}
		return nil
	}

	shutdownContext, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownContext); err != nil {
		return fmt.Errorf("graceful shutdown: %w", err)
	}
	return nil
}

type appConfig struct {
	address        string
	dataFile       string
	token          string
	allowedOrigins []string
	maxBodyBytes   int64
	aiBaseURL      string
	aiAPIKey       string
	aiModel        string
}

func loadConfig() (appConfig, error) {
	config := appConfig{
		address:      envOrDefault("SYNC_ADDR", ":8080"),
		dataFile:     envOrDefault("SYNC_DATA_FILE", "./data/store.json"),
		token:        strings.TrimSpace(os.Getenv("SYNC_TOKEN")),
		maxBodyBytes: defaultMaxBodyBytes,
		aiBaseURL:    envOrDefault("AI_BASE_URL", "https://api.openai.com/v1/chat/completions"),
		aiAPIKey:     strings.TrimSpace(os.Getenv("AI_API_KEY")),
		aiModel:      envOrDefault("AI_MODEL", "gpt-4.1-mini"),
	}
	if strings.TrimSpace(config.token) == "" {
		return appConfig{}, errors.New("SYNC_TOKEN must be set")
	}
	if origins := strings.TrimSpace(os.Getenv("SYNC_CORS_ORIGINS")); origins != "" {
		config.allowedOrigins = strings.Split(origins, ",")
	}
	if rawLimit := strings.TrimSpace(os.Getenv("SYNC_MAX_BODY_BYTES")); rawLimit != "" {
		limit, err := strconv.ParseInt(rawLimit, 10, 64)
		if err != nil || limit <= 0 {
			return appConfig{}, errors.New("SYNC_MAX_BODY_BYTES must be a positive integer")
		}
		config.maxBodyBytes = limit
	}
	return config, nil
}

func envOrDefault(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

func healthcheck() error {
	url := envOrDefault("SYNC_HEALTH_URL", "http://127.0.0.1:8080/health")
	client := &http.Client{Timeout: 3 * time.Second}
	response, err := client.Get(url)
	if err != nil {
		return fmt.Errorf("health request failed: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("health endpoint returned %s", response.Status)
	}
	return nil
}
