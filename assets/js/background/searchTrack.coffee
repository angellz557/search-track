###
# This file keeps track of the Google searches a person performs in the background. It saves them
# in the local storage in the "queries" variable
###
searchTrack = {}
searchTrack.addPageRelation = (url, query, tabId) ->
  #something here
searchTrack.removeTab = (searchInfo, tabId) ->
  idx = searchInfo.tabs.indexOf(tabId)
  searchInfo.tabs.splice(idx, 1) if idx > -1
  searchInfo.save()
  
searchTrack.addTab = (searchInfo, tabId) ->
  searchInfo.tabs.push(tabId) if searchInfo.tabs.indexOf(tabId) < 0
  searchInfo.date = Date.now()
  searchInfo.save()

extractGoogleRedirectURL = (url) ->
  matches = url.match(/www\.google\.com\/.*url=(.*?)($|&)/)
  if matches == null
    return url
  url = decodeURIComponent(matches[1].replace(/\+/g, ' '))
  return url


createOrUpdateSearchInfo = (tabId, tab, query) ->
  db.SearchInfo.where('name').equalsIgnoreCase(query).sortBy("date").then (res) ->
    searchInfo = res[0]
    if !searchInfo
      #First time finding this
      Logger.debug 'creating for: ' + tab.url
      searchInfo = new SearchInfo({name: query, tabs: [tabId], date: Date.now()})
      return searchInfo.save().then (searchInfo) ->
        pageInfo = new PageInfo({isSERP: true, url: tab.url, query: searchInfo.name, tab: tabId, date: Date.now(), referrer: null, visits: 1, title: tab.title})
        pageInfo.save()
    else
      searchInfo.date = Date.now()
      searchInfo.visits += 1
      searchInfo.tabs.push(tabId) if searchInfo.tabs.indexOf(tabId) < 0
      Logger.debug "search found #{searchInfo.name} \n adding tab id #{tabId}"
      return searchInfo.save().then (searchInfo) ->
        db.PageInfo.where('query').equals(query).and((val) -> val.isSERP).first()
      .then (pageInfo) ->
        console.log(pageInfo)
        pageInfo.visits += 1
        pageInfo.tab = tabId
        pageInfo.date = Date.now()
        pageInfo.save()
  .catch (err) ->
    Logger.error("Error updating searchInfo: " + err)


getContentAndTokenize = (tabId, pageInfo) ->
  chrome.tabs.get tabId, (tab) ->
    Logger.debug "TOK:\n" + tab.url
    chrome.tabs.executeScript tabId, {code: 'window.document.documentElement.innerHTML'}, (results) ->
      html = results[0]
      if html? and html.length > 10
        $.ajax(
          type: 'POST',
          url: 'http://104.131.7.171/lda',
          data: { 'data': JSON.stringify( {'html': html} ) }
        ).success( (results) ->
          Logger.debug 'lda'
          results = JSON.parse results
          vector = results['vector']
          pageInfo = _.extend(pageInfo,{title: tab.title, url: tab.url, vector: results['vector'], topics: results['topics'], topic_vector: results['topic_vector'], size: results['size']})
          pageInfo.save().catch (err) ->
            Logger.error err
        ).fail (a, t, e) ->
          Logger.debug "fail tokenize\n" + t


####
#
# Checks for Google queries and new tab navigations
#
####
chrome.tabs.onUpdated.addListener (tabId, changeInfo, tab) ->
  # TODO what if the page keeps loading while the user is reading it?
  # if SearchInfo is created after some link is clicked, the page is not tracked
  if changeInfo.status != 'complete'
    return
  Logger.debug "onUpdated #{tabId} \n #{changeInfo}"

  matches = tab.url.match(/www\.google\.com\/.*q=(.*?)($|&)/)

  if matches != null
    query = decodeURIComponent(matches[1].replace(/\+/g, ' '))
    if query != ""
      createOrUpdateSearchInfo(tabId, tab, query)

####
#
# Check for any webNavication complete events
#
####
chrome.webNavigation.onCompleted.addListener (details) ->
  # subframe navigation
  if details.frameId != 0
    return
  Logger.debug "onCompleted: \n #{details} \n #{details.url}"

#####
#
# When a history element is created, we want to track that
#
#####
chrome.webNavigation.onCommitted.addListener (details) ->
  return if details.frameId != 0
  Logger.info "committed nav: #{details.tabId} -> #{details.url}"
  details.url = extractGoogleRedirectURL details.url
  return Promise.all([
    db.SearchInfo.where('tabs').equals(details.tabId).sortBy("date")
    db.PageInfo.where("tab").equals(details.tabId).sortBy("date")
  ]).spread (res1, res2) ->
    searchInfo = res1[0]
    pageInfo = res2[0]
    if searchInfo
      db.PageInfo.where('url').equals(details.url).and((val) -> val.query == searchInfo.name).first().then (dup_pageInfo) ->
        # check for dup here
        if dup_pageInfo
          if details.transitionQualifiers.indexOf("forward_back") >= 0
            return searchInfo.addTab(searchInfo, details.tabId)
          else if details.transitionType != "reload"
            if Date.now - dup_pageInfo.date / 60000.0 > 0.5
              dup_pageInfo.date = Date.now()
              return dup_pageInfo.save()
        else
          if details.transitionQualifiers.indexOf("from_address_bar") >= 0
            searchTrack.removeTab(searchInfo, details.tabId)
          else if details.transitionQualifiers.indexOf("forward_back") >= 0
            searchTrack.removeTab(searchInfo, details.tabId)
          else if details.transitionType != "reload"
            data = new PageInfo({isSERP: false, url: details.url, query: searchInfo.name, tab: details.tabId, date: Date.now(), referrer: (if pageInfo then pageInfo.id else null), visits: 1, title: ''})
            data.save().then (data) ->
              Logger.info "add tab for: \n #{data} \n to: \n #{searchInfo}"
              getContentAndTokenize(details.tabId, data)
  .catch (err) ->
    Logger.error "Error creating entry on webNavigation #{err}"
    
####
#
# Check when we create new entry when a new window, or a new tab in an existing window is created
#
####
chrome.webNavigation.onCreatedNavigationTarget.addListener (details) ->
  Logger.info 'newTab nav: ' + details.sourceTabId + ' -> ' + details.tabId
  details.url = extractGoogleRedirectURL details.url
  chrome.tabs.get details.sourceTabId, (sourceTab) ->
    db.PageInfo.where('url').equals(sourceTab.url).sortBy("date").then (res) ->
      pageInfo = res[0]
      return Promise.all([pageInfo,db.SearchInfo.where('name').equals(pageInfo.query).sortBy("date")]).spread (pageInfo,res) ->
        searchInfo = res[0]
        if searchInfo
          # add referrer here
          data = new PageInfo({isSERP: false, url: details.url, query: searchInfo.name, tab: details.tabId, date: Date.now(), referrer: pageInfo.id, visits: 1, title: ''})
          return Promise.all([data.save(), searchTrack.addTab(searchInfo, details.tabId)]).spread (pageInfo, searchInfo) ->
            getContentAndTokenize(details.tabId, data)
            Logger.info("Created pageInfo entry \n#{pageInfo} for searchInfo \n#{searchInfo}")
    .catch (err) ->
      Logger.error('WebNavigation onCreatedNavicationTarget error ' + err)