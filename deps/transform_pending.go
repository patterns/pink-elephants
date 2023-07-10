package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"text/template"
	"time"
)
import "github.com/redis/go-redis/v9"

const REDIS_PREFIX = "peop:activity:*"

func main() {
	dir, err := os.Getwd()
	if err != nil {
		log.Panicf("Workdir fault, %v", err)
	}
	temp, err := os.MkdirTemp(dir, "pending")
	if err != nil {
		log.Panicf("Tempdir fault, %v", err)
	}
	tmpl := template.Must(template.New("activity").Parse(activityTemplate))

	opt, err := redis.ParseURL(os.Getenv("REDIS_ADDRESS"))
	if err != nil {
		log.Panicf("Redis address fault, %v", err)
	}

	rdb := redis.NewClient(opt)
	ctx := context.Background()
	stamp := time.Now().UTC().Format(time.RFC3339)
	rownum := 0

	// list of keys (wildcard pattern)
	iter := rdb.Scan(ctx, 0, REDIS_PREFIX, 0).Iterator()
	for iter.Next(ctx) {
		rowid := iter.Val()
		log.Printf("key( %v )", rowid)
		// retrieve row by key
		val, err := rdb.Get(ctx, rowid).Result()
		if err != nil {
			log.Panicf("Row fault, %v", err)
		}
		log.Printf("val, %s", val)
		rownum += 1
		// create markdown file for row
		fname := filepath.Join(temp, fmt.Sprintf("%03d.md", rownum))
		outf, err := os.Create(fname)
		if err != nil {
			log.Printf("Create fault, %v", err)
			break
		}
		defer outf.Close()

		err = tmpl.Execute(outf, Pending{Message: val, Rownum: rownum, Stamp: stamp})
		if err != nil {
			log.Printf("Template exec fault, %v", err)
			break
		}

	}
	if err := iter.Err(); err != nil {
		log.Panicf("Keys list fault, %v", err)
	}

}

const activityTemplate = `
# REQUIRED
title = "Queue Item {{.Rownum}}"
# OPTIONAL
description = "Description of Item {{.Rownum}}"
template = "pending"
[extra]
date = "{{.Stamp}}"

---
{{.Message}}
`

type Pending struct {
	Message, Stamp string
	Rownum         int
}
