inject        = require 'honk-di'
promise       = require 'promise'
setAsPlayed   = require('vistar-html5player').Player.setAsPlayed
{ProofOfPlay} = require 'vistar-html5player'
{AdRequest}   = require 'vistar-html5player'

HC_WARMUP_DURATION          = 5 * 60 * 1000
HC_MAX_CONSECUTIVE_FAILURES = 5

class View
  _config:    inject 'config'
  _cortex:    inject 'cortex'
  _adRequest: inject AdRequest
  _pop:       inject ProofOfPlay

  constructor: ->
    @_queue = []
    @_startTime = new Date().getTime()
    @_consecutiveFailures = 0
    @_current = undefined

  healthCheck: (report) =>
    now = new Date().getTime()
    if now < @_startTime + HC_WARMUP_DURATION
      # Ignore health checks during the warm up period.
      return report status: true

    if @_consecutiveFailures >= HC_MAX_CONSECUTIVE_FAILURES
      @_consecutiveFailures = 0
      return report
        status: false
        reason: 'Ad requests are failing'
        # Player will not try to recover from this failure. The incident will
        # still be reported on dashboard.
        crash:  false

    # TODO(hkaya): We need to check PoP failures as well. Unfortunately,
    # ProofOfPlay doesn't expose server errors at the moment.

    report status: true

  prepare: (offer) =>
    container = window.document.getElementById 'content'
    @_fetch()
      .then (ad) =>
        @_cache ad
          .then =>
            @_createDOMNode container, ad
              .then (node) =>
                offer((done) =>
                  @_render container, ad, node
                    .then =>
                      @_makePoPRequest ad, true
                      done()
                    .catch (e) =>
                      console.error "Failed to render ad #{ad.asset_url}", e
                      @_makePoPRequest ad, false
                      done()
                , {id: ad.asset_url, label: ad.asset_url})
              .catch (e) =>
                console.error 'Failed to create DOM node.', e
                @_makePoPRequest ad, false
                offer()
          .catch (e) =>
            console.error "Failed to cache ad #{ad.asset_url}", e
            @_makePoPRequest ad, false
            offer()
      .catch (e) ->
        console.log "No ads to display. e=#{e?.message}"
        offer()

  _fetch: ->
    new promise (resolve, reject) =>
      if @_queue.length > 0
        ad = @_queue.shift()
        return resolve ad

      @_adRequest.fetch()
        .then (response) =>
          @_consecutiveFailures = 0
          if response?.advertisement?.length > 0
            @_queue = @_queue.concat response.advertisement
            ad = @_queue.shift()
            return resolve ad

          reject()
        .catch (e) =>
          @_consecutiveFailures += 1
          reject e

  _cache: (ad) ->
    opts =
      cache:
        mode: 'normal'
        ttl:  6 * 60 * 60 * 1000

    @_cortex.net.get ad.asset_url, opts

  _isVideo: (ad) ->
    ad?.mime_type?.match /^video/

  _makePoPRequest: (ad, status) ->
    ad = setAsPlayed ad, status
    @_pop.write ad

  _render: (container, ad, node) ->
    new promise (resolve, reject) =>
      p = if @_isVideo ad
        @_renderVideo container, ad, node
      else
        @_renderImage ad, node

      p.then(resolve).catch(reject)

  _renderVideo: (container, ad, node) ->
    new promise (resolve, reject) =>
      onSourceError = (ev) ->
        console.warn "Video player failed to play #{ev?.target?.src}. \
          networkState=#{node?.networkState}, \
          readyState=#{node?.readyState}, mediaError=#{node?.error?.code}"
        reject()

      onVideoEnded = =>
        console.log "Video ad finished: #{ad.asset_url}"
        @_current = ad
        resolve()

      onVideoStalled = (ev) ->
        console.warn "Video player was stalled while playing \
          #{ev?.target?.src}. networkState=#{node?.networkState}, \
          readyState=#{node?.readyState}, mediaError=#{node?.error?.code}"
        reject()

      node.addEventListener 'ended', onVideoEnded
      node.addEventListener 'stalled', onVideoStalled
      node.firstChild?.addEventListener 'error', onSourceError

      @_hideCurrent()
      node.style.setProperty 'z-index', 9999
      container.appendChild node
      node.play()

  _renderImage: (ad, node) ->
    new promise (resolve, reject) =>
      @_hideCurrent()
      node.style.setProperty 'z-index', 9999

      end = =>
        console.log "Image ad finished: #{ad.asset_url}"
        @_current = ad
        resolve()
      setTimeout end, ad.length_in_milliseconds

  _hideCurrent: ->
    if not @_current?
      return

    if @_isVideo @_current
      current = document.getElementById @_current.id
      if current?
        container = document.getElementById 'content'
        container.removeChild current

    else
      current = document.getElementById @_current.asset_url
      current?.style.setProperty 'z-index', -9999

    @_current = undefined

  _createDOMNode: (container, ad) ->
    new promise (resolve, reject) =>
      node = undefined
      if @_isVideo ad
        node = window.document.createElement 'video'
        # we want one video tag per video ad.
        node.id = ad.id
        node.setAttribute 'autoplay', false
        node.setAttribute 'preload', 'auto'
        node.setAttribute 'muted', not @_config['vistar.allow_audio']
        node.style.setProperty 'z-index', 9999

        node.addEventListener 'canplaythrough', ->
          resolve node

        source = window.document.createElement 'source'
        source.src = ad.asset_url
        node.appendChild source

      else
        node = document.getElementById ad.asset_url
        if node?
          return resolve node

        node = new Image()
        # we want one image tag per url.
        node.id = ad.asset_url
        node.onerror = reject
        node.onload = ->
          resolve node
        node.src = ad.asset_url
        container.appendChild node

module.exports = View
