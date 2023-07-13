package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
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
		pend := jsFields(val, rownum)
		// create markdown file for row
		fpath := fmtFilepath(temp, pend)
		outf, err := os.Create(fpath)
		if err != nil {
			log.Printf("Create fault, %v", err)
			break
		}
		defer outf.Close()
		err = tmpl.Execute(outf, pend)
		/*
			err = tmpl.Execute(outf, Pending{
				Message: val,
				Rownum: rownum,
				Stamp: stamp,
			})*/
		if err != nil {
			log.Printf("Template exec fault, %v", err)
			break
		}

	}
	if err := iter.Err(); err != nil {
		log.Panicf("Keys list fault, %v", err)
	}

}

// file name (uses timestamp pattern for sorting)
func fmtFilepath(dir string, p *Pending) string {
	// attempt to extract timestamp from payload
	prefix := p.Timestamp.Format(time.DateOnly)
	return filepath.Join(dir, fmt.Sprintf("%s-%03d.md", prefix, p.Rownum))
}

func jsFields(js string, rownum int) *Pending {
	var input string

	// in debug, expect ##DEBUG## marker
	sl := strings.Split(js, "##DEBUG##")
	if len(sl) == 1 {
		// non-debug payload
		input = sl[0]
	} else {
		// todo inspect http headers were appended as second half
		input = sl[0]
	}

	var f interface{}
	err := json.Unmarshal([]byte(input), &f)
	if err != nil {
		log.Panicf("Unmarshal fault, %v", err)
	}
	var (
		id        string
		activity  string
		published string
	)
	m := f.(map[string]interface{})
	for k, v := range m {
		switch strings.ToLower(k) {
		case "id":
			id = v.(string)
		case "published":
			published = v.(string)
		case "type":
			activity = v.(string)
		}
	}
	// fallback timestamp
	ts := time.Now().UTC()
	if published == "" {
		published = ts.Format(time.RFC3339)
	} else {
		pt, err := time.Parse(time.RFC3339, published)
		if err != nil {
			log.Printf("RFC3339 expected, %v", err)
		} else {
			ts = pt
		}
	}

	return &Pending{
		Message:   js,
		Date:      published,
		Rownum:    rownum,
		Activity:  activity,
		Reference: id,
		Timestamp: ts,
	}
}

const activityTemplate = `
# REQUIRED
title = "Queue Item {{.Rownum}}"
# OPTIONAL
description = "Description of Item {{.Rownum}}"
template = "pending"
[extra]
date = "{{.Date}}"
activity = "{{.Activity}}"
reference = "{{.Reference}}"

---
{{.Message}}
`

type Pending struct {
	Message, Date, Activity, Reference string
	Rownum                             int
	Timestamp                          time.Time
}
