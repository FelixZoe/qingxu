package httpapi

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

const maxAIContentBytes = 80 << 10

type aiService struct {
	baseURL string
	apiKey  string
	model   string
	client  *http.Client
}

type aiInput struct {
	Mode    string   `json:"mode"`
	Title   string   `json:"title,omitempty"`
	Content string   `json:"content,omitempty"`
	Goal    string   `json:"goal,omitempty"`
	Tasks   []aiTask `json:"tasks,omitempty"`
	Prompt  string   `json:"prompt,omitempty"`
}

type aiTask struct {
	Title       string `json:"title"`
	ScheduledAt string `json:"scheduledAt,omitempty"`
}

type chatCompletionRequest struct {
	Model       string        `json:"model"`
	Messages    []chatMessage `json:"messages"`
	Temperature float64       `json:"temperature"`
}

type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type chatCompletionResponse struct {
	Choices []struct {
		Message chatMessage `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

func newAIService(baseURL, apiKey, model string) *aiService {
	apiKey = strings.TrimSpace(apiKey)
	if apiKey == "" {
		return nil
	}
	return &aiService{
		baseURL: strings.TrimSpace(baseURL),
		apiKey:  apiKey,
		model:   strings.TrimSpace(model),
		client:  &http.Client{Timeout: 50 * time.Second},
	}
}

func (s *Server) aiRequest(response http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodPost {
		response.Header().Set("Allow", http.MethodPost)
		writeError(response, http.StatusMethodNotAllowed, "method_not_allowed", "only POST is allowed")
		return
	}
	if !s.requireAuthorization(response, request) {
		return
	}
	if s.ai == nil {
		writeError(response, http.StatusServiceUnavailable, "ai_not_configured", "AI service is not configured")
		return
	}

	request.Body = http.MaxBytesReader(response, request.Body, maxAIContentBytes)
	defer request.Body.Close()
	decoder := json.NewDecoder(request.Body)
	decoder.DisallowUnknownFields()
	var input aiInput
	if err := decoder.Decode(&input); err != nil {
		s.writeDecodeError(response, err)
		return
	}
	if err := requireEOF(decoder); err != nil {
		s.writeDecodeError(response, err)
		return
	}

	system, prompt, err := buildAIPrompt(input)
	if err != nil {
		writeError(response, http.StatusBadRequest, "invalid_ai_request", err.Error())
		return
	}
	text, err := s.ai.complete(request, system, prompt)
	if err != nil {
		writeError(response, http.StatusBadGateway, "ai_request_failed", "AI service is temporarily unavailable")
		return
	}
	writeJSON(response, http.StatusOK, map[string]string{"text": text})
}

func buildAIPrompt(input aiInput) (string, string, error) {
	switch strings.TrimSpace(input.Mode) {
	case "rss_summary":
		content := strings.TrimSpace(input.Content)
		if content == "" {
			return "", "", errors.New("content is required")
		}
		if len(content) > 60_000 {
			content = content[:60_000]
		}
		instruction := strings.TrimSpace(input.Prompt)
		if instruction == "" {
			instruction = "请用三段输出：一句话结论；3 个关键点；值得采取的一个行动。总计不超过 260 个汉字。"
		}
		return "你是克制、准确的中文阅读助手。只根据原文作答，不编造事实。输出纯文本，不使用 Markdown 标题。",
			fmt.Sprintf("文章标题：%s\n\n原文：\n%s\n\n摘要要求：%s", strings.TrimSpace(input.Title), content, instruction), nil
	case "task_plan":
		if len(input.Tasks) == 0 && strings.TrimSpace(input.Goal) == "" {
			return "", "", errors.New("tasks or goal is required")
		}
		if len(input.Tasks) > 200 {
			return "", "", errors.New("at most 200 tasks are allowed")
		}
		tasks, _ := json.Marshal(input.Tasks)
		return "你是轻量任务规划助手。保持现实、少而明确，不制造冗余任务。必须只输出合法 JSON，不要代码块。",
			fmt.Sprintf("用户目标：%s\n现有任务：%s\n今天日期：%s\n请返回 {\"summary\":\"一句简短建议\",\"suggestions\":[{\"title\":\"任务名\",\"dayOffset\":0}]}。dayOffset 为 0 到 14，最多 6 项；保留必要的原任务，可拆分过大的任务。", strings.TrimSpace(input.Goal), tasks, time.Now().Format("2006-01-02")), nil
	case "rss_translation":
		content := strings.TrimSpace(input.Content)
		var segments []string
		if err := json.Unmarshal([]byte(content), &segments); err != nil || len(segments) == 0 {
			return "", "", errors.New("content must be a non-empty JSON string array")
		}
		if len(segments) > 40 {
			return "", "", errors.New("at most 40 translation segments are allowed")
		}
		return "你是专业翻译器。把输入 JSON 字符串数组逐项翻译成自然、准确的简体中文。保持数组数量和顺序完全一致，只输出合法 JSON 数组，不要解释，不要 Markdown。",
			fmt.Sprintf("待翻译 JSON 数组：\n%s", content), nil
	default:
		return "", "", errors.New("unsupported mode")
	}
}

func (a *aiService) complete(request *http.Request, system, prompt string) (string, error) {
	payload, err := json.Marshal(chatCompletionRequest{
		Model: a.model,
		Messages: []chatMessage{
			{Role: "system", Content: system},
			{Role: "user", Content: prompt},
		},
		Temperature: 0.2,
	})
	if err != nil {
		return "", err
	}
	req, err := http.NewRequestWithContext(request.Context(), http.MethodPost, a.baseURL, bytes.NewReader(payload))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+a.apiKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	resp, err := a.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil {
		return "", err
	}
	var completion chatCompletionResponse
	if err := json.Unmarshal(body, &completion); err != nil {
		return "", err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		if completion.Error != nil {
			return "", errors.New(completion.Error.Message)
		}
		return "", fmt.Errorf("AI endpoint returned %s", resp.Status)
	}
	if len(completion.Choices) == 0 || strings.TrimSpace(completion.Choices[0].Message.Content) == "" {
		return "", errors.New("AI endpoint returned an empty response")
	}
	return strings.TrimSpace(completion.Choices[0].Message.Content), nil
}
