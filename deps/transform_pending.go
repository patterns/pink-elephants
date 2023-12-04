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

const REDIS_PREFIX = "pnklph:activity:*"
const ACTOR_ADAFRUIT = "https://mastodon.cloud/users/adafruit"

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
	totalDel := 0

	// list of keys (wildcard pattern)
	iter := rdb.Scan(ctx, 0, REDIS_PREFIX, 0).Iterator()
	for iter.Next(ctx) {
		rowid := iter.Val()
		////log.Printf("key( %v )", rowid)
		// retrieve row by key
		val, err := rdb.Get(ctx, rowid).Result()
		if err != nil {
			log.Panicf("Row fault, %v", err)
		}
		////log.Printf("val, %s", val)
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
		if err != nil {
			log.Printf("Template exec fault, %v", err)
			break
		}

		// post-process
		if pend.Activity == "Delete" {
			// since we don't cache activitypub data (which would update)
			// simply prune these "Delete" tickets
			rdb.Del(ctx, rowid)
			totalDel += 1
		} else if !strings.HasPrefix(pend.Actor, ACTOR_ADAFRUIT) {
			// "only want actor of adafruit"
			// subscribed to adafruit, so we're pruning activity from others
			// (todo I think this is the beginning of need for rules engine)
			rdb.Del(ctx, rowid)
			totalDel += 1
		}
	}
	if err := iter.Err(); err != nil {
		log.Panicf("Keys list fault, %v", err)
	}
	rdb.Close()
	// summary
	log.Printf("Done. (%d deleted of %d total)", totalDel, rownum)
}

// file name (uses timestamp pattern for sorting)
func fmtFilepath(dir string, p *Pending) string {
	// attempt to extract timestamp from payload
	prefix := p.Timestamp.Format("2006-366")
	return filepath.Join(dir, fmt.Sprintf("%s-%03d.md", prefix, p.Rownum))
}

func jsFields(js string, rownum int) *Pending {
	// in debug, expect ##DEBUG## marker
	var sl = strings.Split(js, "##DEBUG##")
	if len(sl) > 1 && len(sl[0]) == 0 {
		// empty http body, arrived on /outbox endpoint?
		return plainFields(sl[1], rownum)
	}
	// non-debug payload
	var input = sl[0]

	var f interface{}
	err := json.Unmarshal([]byte(input), &f)
	if err != nil {
		log.Panicf("Unmarshal fault, %v", err)
	}
	var (
		id        string
		activity  string
		published string
		actor     string
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
		case "actor":
			actor = v.(string)

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
		Actor:     actor,
	}
}
func plainFields(raw string, rownum int) *Pending {
	var (
		id        string
		activity  string
		published string
		actor     string
	)
	var sl = strings.Split(raw, "\r\n")
	for _, v := range sl {
		pair := strings.Split(v, ": ")
		switch pair[0] {
		case "signature":
			id = fmt.Sprintf("record-%03d", rownum)
			actor = scanKeyId(pair[1])
		case "date":
			published = pair[1]
		case "spin-matched-route":
			activity = pair[1]

		}
	}
	pt, err := time.Parse(time.RFC1123, published)
	if err != nil {
		log.Printf("RFC1123 expected, %v", err)
	}

	return &Pending{
		Message:   raw,
		Date:      pt.Format(time.RFC3339),
		Rownum:    rownum,
		Activity:  activity,
		Reference: id,
		Timestamp: pt,
		Actor:     actor,
	}
}

func scanKeyId(in string) string {
	// expect 'keyId=stuff, remaing-subheader'
	var sl = strings.Split(in, ",")
	for _, v := range sl {
		if strings.HasPrefix(v, "keyId=") {
			return strings.TrimPrefix(v, "keyId=")
		}
	}
	return ""
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
	Message, Date, Activity, Reference, Actor string
	Rownum                                    int
	Timestamp                                 time.Time
}
