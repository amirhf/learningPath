package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()

	r.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	r.POST("/api/resources/search", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"todo": "proxy to rag-service /search"})
	})

	r.Run(":8080")
}
