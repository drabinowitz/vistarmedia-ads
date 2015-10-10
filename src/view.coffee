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
      if @_current?
        current = document.getElementById @_current.asset_url
        if current?
          container.removeChild current

        @_current = undefined

      onSourceError = (ev) ->
        console.warn "Video player failed to play #{ev?.target?.src}. \
          networkState=#{video?.networkState}, \
          readyState=#{video?.readyState}, mediaError=#{video?.error?.code}"
        reject()

      onVideoEnded = ->
        console.info "Video ended successfully: #{ad.asset_url}"
        resolve()

      onVideoStalled = (ev) ->
        console.warn "Video player was stalled while playing \
          #{ev?.target?.src}. networkState=#{video?.networkState}, \
          readyState=#{video?.readyState}, mediaError=#{video?.error?.code}"
        reject()

      node.addEventListener 'ended', onVideoEnded
      node.addEventListener 'stalled', onVideoStalled

      source = window.document.createElement 'source'
      source.addEventListener 'error', onSourceError
      source.setAttribute 'src', ad.asset_url
      video.appendChild source

      container.appendChild video
      @_current = ad

  _renderImage: (ad, node) ->
    new promise (resolve, reject) =>
      if @_current?
        current = document.getElementById @_current.asset_url
        if current?
          # At any time we'll have only a handful active ads. Instead of
          # removing the image nodes we push them back to avoid the browser
          # to decode images again.
          # TODO(hkaya): We should add a limit to the cached DOM nodes.
          current.style.setProperty 'z-index', -9999
        @_current = undefined

      node.style.setProperty 'z-index', 9999
      end = =>
        console.log "Image ad finished: #{ad.asset_url}"
        @_current = ad
        resolve()
      setTimeout end, ad.length_in_milliseconds

  _createDOMNode: (container, ad) ->
    new promise (resolve, reject) =>
      node = undefined
      if @_isVideo ad
        node = window.document.createElement 'video'
        node.id = ad.asset_url
        node.setAttribute 'autoplay', true
        node.setAttribute 'muted', not @_config['vistar.allow_audio']

        # TODO(hkaya): It will be better if we attach the source to the video
        # node here. However, we need to make sure events will still get fired
        # during the render call. Current implementation is safer but adds
        # some overhead to the render call.

      else
        node = document.getElementById ad.asset_url
        if not node?
          node = new Image()
          node.id = ad.asset_url
          node.onerror = reject
          node.onload = ->
            resolve node
          node.src = ad.asset_url
          container.appendChild node
          return

      resolve node

module.exports = View
