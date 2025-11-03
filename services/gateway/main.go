package main

import (
    "bytes"
    "encoding/json"
    "io"
    "log"
    "net/http"
    "os"
    "strconv"

    "github.com/gin-gonic/gin"
)

type searchFilters struct {
    LevelLTE   *int      `json:"level_lte,omitempty"`
    LicenseIn  []string  `json:"license_in,omitempty"`
    DurationLTE *int     `json:"duration_lte,omitempty"`
    MediaIn    []string  `json:"media_in,omitempty"`
}

type ragSearchRequest struct {
    Query  string        `json:"query"`
    TopK   int           `json:"top_k"`
    Filters *searchFilters `json:"filters,omitempty"`
}

func main() {
    r := gin.Default()

    ragBase := os.Getenv("RAG_BASE_URL")
    if ragBase == "" {
        log.Println("WARNING: RAG_BASE_URL not set; /api/resources/search will fail")
    }

    r.GET("/healthz", func(c *gin.Context) {
        c.JSON(http.StatusOK, gin.H{"status": "ok"})
    })

    // GET /api/resources/search?query=...&top_k=...&level=...&license=a,b&duration=...&media=video,reading
    r.GET("/api/resources/search", func(c *gin.Context) {
        query := c.Query("query")
        if query == "" {
            // support fallback "q"
            query = c.Query("q")
        }
        if query == "" {
            c.JSON(http.StatusBadRequest, gin.H{"error": "missing query"})
            return
        }

        // Build filters
        var f *searchFilters
        var levelPtr *int
        var durationPtr *int
        if lvlStr := c.Query("level"); lvlStr != "" {
            if v, err := strconv.Atoi(lvlStr); err == nil {
                levelPtr = &v
            }
        }
        var licenses []string
        if ls := c.Query("license"); ls != "" {
            licenses = splitCSV(ls)
        }
        var media []string
        if ms := c.Query("media"); ms != "" {
            media = splitCSV(ms)
        }
        if levelPtr != nil || len(licenses) > 0 || durationPtr != nil || len(media) > 0 {
            f = &searchFilters{LevelLTE: levelPtr, LicenseIn: licenses, DurationLTE: durationPtr, MediaIn: media}
        }

        topK := 20
        if tk := c.Query("top_k"); tk != "" {
            if v, err := strconv.Atoi(tk); err == nil && v > 0 {
                topK = v
            }
        }

        reqBody := ragSearchRequest{Query: query, TopK: topK, Filters: f}
        b, _ := json.Marshal(reqBody)
        url := ragBase + "/search"
        httpReq, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(b))
        if err != nil {
            c.JSON(http.StatusInternalServerError, gin.H{"error": "request build failed"})
            return
        }
        httpReq.Header.Set("Content-Type", "application/json")

        // propagate trace headers if present
        if tp := c.GetHeader("traceparent"); tp != "" {
            httpReq.Header.Set("traceparent", tp)
        }

        resp, err := http.DefaultClient.Do(httpReq)
        if err != nil {
            c.JSON(http.StatusBadGateway, gin.H{"error": "rag-service unreachable", "detail": err.Error()})
            return
        }
        defer resp.Body.Close()

        c.Status(resp.StatusCode)
        c.Header("Content-Type", resp.Header.Get("Content-Type"))
        if _, err := io.Copy(c.Writer, resp.Body); err != nil {
            c.JSON(http.StatusBadGateway, gin.H{"error": "failed to read rag response"})
        }
    })

    r.Run(":8080")
}

// splitCSV splits comma-separated values and trims spaces
func splitCSV(s string) []string {
    var out []string
    start := 0
    for i := 0; i <= len(s); i++ {
        if i == len(s) || s[i] == ',' {
            part := s[start:i]
            // trim spaces
            j := 0
            k := len(part)
            for j < k && (part[j] == ' ' || part[j] == '\t') {
                j++
            }
            for k > j && (part[k-1] == ' ' || part[k-1] == '\t') {
                k--
            }
            if j < k {
                out = append(out, part[j:k])
            }
            start = i + 1
        }
    }
    return out
}
