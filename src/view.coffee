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
    @_fetch()
      .then (ad) =>
        @_cache ad
          .then =>
            offer((done) =>
              @_render ad
                .then =>
                  @_makePoPRequest ad, true
                  done()
                .catch (e) =>
                  console.error "Failed to render ad #{ad.asset_url}", e
                  @_makePoPRequest ad, false
                  done()
            , {id: ad.asset_url, label: ad.asset_url})
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

  _render: (ad) ->
    new promise (resolve, reject) =>
      content = window.document.getElementById 'content'
      while content.firstChild?
        content.removeChild content.firstChild

      if @_isVideo ad
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

        video = window.document.createElement 'video'
        video.setAttribute 'autoplay', true
        video.setAttribute 'muted', not @_config['vistar.allow_audio']
        video.style.setProperty 'width', '100%'
        video.style.setProperty 'height', '100%'

        source = window.document.createElement 'source'
        source.addEventListener 'error', onSourceError
        source.setAttribute 'src', ad.asset_url

        video.addEventListener 'ended', onVideoEnded
        video.addEventListener 'stalled', onVideoStalled
        video.appendChild source
        content.appendChild video

      else
        url = ad.asset_url
        div = window.document.createElement 'div'
        div.setAttribute 'class', 'image-ad'
        div.style.setProperty 'background', "url(#{url})"
        div.style.setProperty 'background-repeat', 'no-repeat'
        div.style.setProperty 'background-position', '50% 50%'
        div.style.setProperty 'background-size', 'contain'
        div.style.setProperty 'overflow', 'hidden'
        content.appendChild div

        end = ->
          console.log "Image ad finished: #{url}"
          resolve()

        setTimeout end, ad.length_in_milliseconds

module.exports = View
