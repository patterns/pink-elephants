
title = "Overview"
description = "Brief Tour of Subsystems from 3000m Elevation"
template = "blurb"

[extra]
date = "2023-07-01T23:59:19Z"

---
<h1 class="title">Diagram</h1>
<div>
<h2 class="subtitle">Legend</h2>
<p>JSON - static files such as the content for webfinger, and the actor</p>
<p>WASM - components which implement the *handler interface* from Spin</p>
<p>Spin - webassembly framework by Fermyon</p>
<p>Proxy - we forward to our external server to retrieve verifier/public keys</p>
<p>Redis - storage of activity queues (for inbox/outbox)</p>
</div>

