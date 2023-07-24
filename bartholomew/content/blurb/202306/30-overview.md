
title = "Overview"
description = "A introduction to PEoP"
template = "blurb"

[extra]
date = "2023-06-30T23:59:19Z"

---
<h1 class="title is-4">PEoP</h1>
<div>
<figure class="image "><img src="/static/diagram-peop.svg"></figure>
</div>

<h1 class="title is-4">Sequence Diagram</h1>
<div>
<figure class="image "><img src="/static/diagram-inbox.svg"></figure>

<p>JSON - static files such as the content for webfinger, and the actor</p>
<p>WASM - components which implement the *handler interface* from Spin</p>
<p>Spin - webassembly framework by Fermyon</p>
<p>Proxy - we forward to our external server to retrieve verifier/public keys</p>
<p>Redis - storage of activity queues (for inbox/outbox)</p>
</div>

