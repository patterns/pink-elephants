# pink-elephants

<picture>
 <source media="(prefers-color-scheme: dark)" srcset="/bartholomew/static/diagram-dark-peop.png">
 <source media="(prefers-color-scheme: light)" srcset="/bartholomew/static/diagram-peop.svg">
 <img alt="diagram" src="/bartholomew/static/diagram-peop.svg">
</picture>

## Quickstart
```bash
export SPIN_CONFIG_SELF_ACTOR="echo" 
export SPIN_CONFIG_SITE_NAME="cloud-start-demo"
export SPIN_CONFIG_DOMAIN_BASE="fermyon.app" 
export SPIN_CONFIG_REDIS_SERVER="my-demo.us-central1.gce.cloud.redislabs.com:1122" 
export SPIN_CONFIG_REDIS_LOGIN="my-demo-username" 
export SPIN_CONFIG_VERIFIER_PROXY="my-verifier-proxy.pages.dev" 
export SPIN_CONFIG_VERIFIER_BEARER="my-shared-verifier-token" 
spin up --from-registry ghcr.io/patterns/pink-elephants:latest

# in a separate tmux tab
curl --verbose http://localhost:3000
```

## Mahalo
Honk
  by [Ted Unangst](https://humungus.tedunangst.com/r/honk) ([LICENSE](https://humungus.tedunangst.com/r/honk/v/tip/f/LICENSE))

ActivityPub deconstructed
  by [Tom MacWright](https://macwright.com/2022/12/09/activitypub.html)

Mastodon in 6 static pages
  by [Justin Garrison](https://github.com/rothgar/static-mastodon/) ([LICENSE](https://github.com/rothgar/static-mastodon/blob/main/LICENSE))

Inbox
  by [Darius Kazemi](https://github.com/dariusk/express-activitypub) ([LICENSE](https://github.com/dariusk/express-activitypub/blob/master/LICENSE-MIT))

Spin SDK
 by [Ethan Lewis](https://github.com/elewis787/spin-zig) ([LICENSE](https://github.com/elewis787/spin-zig/blob/main/LICENSE))

Malloc, free
 by [Wazero](https://wazero.io/languages/zig/)

Interfaces
 by [Yigong Liu](https://github.com/yglcode/zig_interfaces)

Zig fmt workflow
 by [Bun.sh](https://github.com/oven-sh/bun/)

Sequence diagrams
 by [Kevin Hakanson](https://aws.amazon.com/blogs/architecture/sequence-diagrams-enrich-your-understanding-of-distributed-architectures/)

PlantUML AWS
 by [AWS Labs](https://github.com/awslabs/aws-icons-for-plantuml)

