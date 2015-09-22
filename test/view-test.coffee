require './test-case'
expect  = require('chai').expect
sinon   = require 'sinon'
promise = require 'promise'

View = require '../src/view'

describe 'View', ->
  beforeEach ->
    @clock = sinon.useFakeTimers()
    global.window.document.createElement.returns
      href: ''
      search: ''

    @view = @injector.getInstance View

  afterEach ->
    @clock.restore()

  it 'should start with an empty queue', ->
    expect(@view._queue).to.deep.equal []

  describe '#healthCheck', ->
    beforeEach ->
      @report = sinon.stub()

    it 'should pass during the warmup period', ->
      @view._consecutiveFailures = 100
      @view.healthCheck @report
      expect(@report).to.have.been.calledOnce
      expect(@report).to.have.been.calledWith status: true
      @report.reset()
      @clock.tick 4 * 60 * 1000

      @view.healthCheck @report
      expect(@report).to.have.been.calledOnce
      expect(@report).to.have.been.calledWith status: true

    it 'should fail when there are too many ad request failures', ->
      @view._consecutiveFailures = 100
      @clock.tick 10 * 60 * 1000
      @view.healthCheck @report
      expect(@report).to.have.been.calledOnce
      expect(@report).to.have.been.calledWith
        status: false
        crash: false
        reason: 'Ad requests are failing'
      expect(@view._consecutiveFailures).to.equal 0

    it 'should pass when everything is alright', ->
      @view._consecutiveFailures = 3
      @clock.tick 10 * 60 * 1000
      @view.healthCheck @report
      expect(@report).to.have.been.calledOnce
      expect(@report).to.have.been.calledWith status: true
      expect(@view._consecutiveFailures).to.equal 3

  describe '#prepare', ->
    it 'should call offer when fetch fails', (done) ->
      offer = sinon.stub()
      fetch = sinon.stub @view, '_fetch', ->
        new promise (resolve, reject) -> reject()
      @view.prepare offer
      process.nextTick ->
        expect(fetch).to.have.been.calledOnce
        expect(offer).to.have.been.calledOnce
        expect(offer.args).to.deep.equal [[]]
        done()

    it 'should call offer when cache fails', (done) ->
      offer = sinon.stub()
      fetch = sinon.stub @view, '_fetch', ->
        new promise (resolve, reject) -> resolve 'ad'
      cache = sinon.stub @view, '_cache', ->
        new promise (resolve, reject) -> reject()
      pop = sinon.stub @view, '_makePoPRequest', ->
      @view.prepare offer
      process.nextTick ->
        expect(fetch).to.have.been.calledOnce
        expect(cache).to.have.been.calledOnce
        expect(cache).to.have.been.calledWith 'ad'
        expect(pop).to.have.been.calledOnce
        expect(pop).to.have.been.calledWith 'ad', false
        expect(offer).to.have.been.calledOnce
        expect(offer.args).to.deep.equal [[]]
        done()

    it 'should offer a view with id and label', (done) ->
      offer = sinon.stub()
      ad =
        asset_url: 'url'
      fetch = sinon.stub @view, '_fetch', ->
        new promise (resolve, reject) -> resolve ad
      cache = sinon.stub @view, '_cache', ->
        new promise (resolve, reject) -> resolve()
      @view.prepare offer
      process.nextTick ->
        expect(fetch).to.have.been.calledOnce
        expect(cache).to.have.been.calledOnce
        expect(cache).to.have.been.calledWith ad
        expect(offer).to.have.been.calledOnce
        expect(offer.args[0]).to.have.length 2
        expect(offer.args[0][1]).to.deep.equal
          id: 'url'
          label: 'url'
        done()

    context 'offered view', ->
      it 'should render an ad', (done) ->
        offer = sinon.stub()
        ad =
          asset_url: 'url'
        fetch = sinon.stub @view, '_fetch', ->
          new promise (resolve, reject) -> resolve ad
        cache = sinon.stub @view, '_cache', ->
          new promise (resolve, reject) -> resolve()
        render = sinon.stub @view, '_render', ->
          new promise (resolve, reject) -> resolve()
        pop = sinon.stub @view, '_makePoPRequest', ->
        @view.prepare offer
        process.nextTick ->
          expect(offer).to.have.been.calledOnce
          expect(offer.args[0]).to.have.length 2
          viewDone = sinon.stub()
          offer.args[0][0] viewDone
          expect(render).to.have.been.calledOnce
          expect(render).to.have.been.calledWith ad
          process.nextTick ->
            expect(pop).to.have.been.calledOnce
            expect(pop).to.have.been.calledWith ad, true
            expect(viewDone).to.have.been.calledOnce
            done()

      it 'should expire an ad when render fails', (done) ->
        offer = sinon.stub()
        ad =
          asset_url: 'url'
        fetch = sinon.stub @view, '_fetch', ->
          new promise (resolve, reject) -> resolve ad
        cache = sinon.stub @view, '_cache', ->
          new promise (resolve, reject) -> resolve()
        render = sinon.stub @view, '_render', ->
          new promise (resolve, reject) -> reject()
        pop = sinon.stub @view, '_makePoPRequest', ->
        @view.prepare offer
        process.nextTick ->
          expect(offer).to.have.been.calledOnce
          expect(offer.args[0]).to.have.length 2
          viewDone = sinon.stub()
          offer.args[0][0] viewDone
          expect(render).to.have.been.calledOnce
          expect(render).to.have.been.calledWith ad
          process.nextTick ->
            expect(pop).to.have.been.calledOnce
            expect(pop).to.have.been.calledWith ad, false
            expect(viewDone).to.have.been.calledOnce
            done()

  describe '#_fetch', ->
    it 'should consume an ad from the queue', (done) ->
      fetch = sinon.spy @view._adRequest, 'fetch'
      @view._queue = ['ad1', 'ad2']
      @view._fetch()
        .then (ad) =>
          expect(ad).to.equal 'ad1'
          expect(@view._queue).to.deep.equal ['ad2']
          expect(fetch).to.not.have.been.called
          done()

  describe '#_fetch', ->
    it 'should consume an ad from the queue', (done) ->
      fetch = sinon.spy @view._adRequest, 'fetch'
      @view._queue = ['ad1', 'ad2']
      @view._fetch()
        .then (ad) =>
          expect(ad).to.equal 'ad1'
          expect(@view._queue).to.deep.equal ['ad2']
          expect(fetch).to.not.have.been.called
          done()

    it 'should add newly fetched ads to the queue', (done) ->
      fetch = sinon.stub @view._adRequest, 'fetch', ->
        new promise (resolve, reject) ->
          resolve
            advertisement: ['ad1', 'ad2']
      expect(@view._queue).to.deep.equal []
      @view._consecutiveFailures = 5
      @view._fetch()
        .then (ad) =>
          expect(ad).to.equal 'ad1'
          expect(@view._consecutiveFailures).to.equal 0
          expect(@view._queue).to.deep.equal ['ad2']
          expect(fetch).to.have.been.calledOnce
          done()

    it 'should fail when there are no ads', (done) ->
      fetch = sinon.stub @view._adRequest, 'fetch', ->
        new promise (resolve, reject) ->
          resolve advertisement: []
      expect(@view._queue).to.deep.equal []
      @view._consecutiveFailures = 5
      @view._fetch().catch =>
        expect(@view._consecutiveFailures).to.equal 0
        done()

    it 'should fail when fetch fails', (done) ->
      fetch = sinon.stub @view._adRequest, 'fetch', ->
        new promise (resolve, reject) -> reject()
      expect(@view._queue).to.deep.equal []
      expect(@view._consecutiveFailures).to.equal 0
      @view._fetch().catch =>
        expect(@view._consecutiveFailures).to.equal 1
        done()
