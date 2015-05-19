/*
	Background page for the Forager part of the extension 
*/

// TODO: why is angular loading twice?

task = "default";
console.log(task);

var currentTab;
var lastTab;

chrome.storage.local.clear();
chrome.storage.sync.clear(function() {
  SavedInfo.db.insert({annotation:""}).callback(function() {
    var annotation = SavedInfo.db().get()[0].annotation;
    console.log(annotation);

    // Inject sidebar to every updated page
    chrome.tabs.onUpdated.addListener(function(tabId, changeInfo, tab) {
      chrome.tabs.insertCSS(null, {file: "/css/sidebar.css", runAt: "document_start"}, function() {
      chrome.tabs.executeScript(
      null, {file: '/vendor/jquery/dist/jquery.min.js', runAt: "document_start"}, function() {
      chrome.tabs.executeScript(
      null, {file: '/vendor/taffydb/taffy-min.js', runAt: "document_start"}, function() {
      chrome.tabs.executeScript(
      null, {file: '/vendor/underscore/underscore-min.js', runAt: "document_start"}, function() {
      chrome.tabs.executeScript(
      null, {file: '/js/trackAPI.js', runAt: "document_start"}, function() {
      chrome.tabs.executeScript(
      null, {file: '/vendor/angular/angular.js', runAt: "document_start"}, function() {
      /* chrome.tabs.executeScript(
      null, {file: '/js/content/hoverintent.js', runAt: "document_start"}, function() { */
      chrome.tabs.executeScript(
      null, {file: '/vendor/bootstrap/dist/js/bootstrap.min.js', runAt: "document_start"}, function() {
      chrome.tabs.executeScript(
      null, {file: '/js/interact.min.js', runAt: "document_start"}, function() { 	// For some reason, won't work in vendor 
      chrome.tabs.executeScript(
      null, {file: '/js/content/injectsidebar.js', runAt: "document_start"});	
      });});});});});});});});
    });

  });
});

// Message passing from content scripts and new tab page
chrome.runtime.onMessage.addListener(
   function(request, sender, sendResponse) {
    console.log(sender.tab ?
                "from a content script:" + sender.tab.url :
                "from the extension");
		if (request.newTask) {
			task = request.task;
		} else if (request.newVisual) {
			chrome.runtime.sendMessage({task: task}, function(response) {
				console.log('sent current task'); // doesn't work 
     		});
		} else if (request.changed) { // annotation changed
      changed(request.changed);
      sendResponse({farewell:'changed'});
		} else if (request.changedLoc) { // dragged tab to new location on some page - tell others
      chrome.tabs.query({}, function(tabs) {
        tabs.forEach(function(tab) {
          chrome.tabs.sendMessage(tab.id, {newLoc: request.changedLoc});
        });
        sendResponse({farewell:'moved'});
      });
		} else if (request.deleted) { // deleted a tab - tell others
      chrome.tabs.query({}, function(tabs) {
        tabs.forEach(function(tab) {
          chrome.tabs.sendMessage(tab.id, {delTab: request.deleted});
        });
        sendResponse({farewell:'deleted'});
      });
    } else if (request.changeUrl) {
      chrome.tabs.update(request.changeUrl[0], {selected:true}, function() {
        if (chrome.runtime.lastError) chrome.tabs.create({'url': request.changeUrl[1]});
      });
    }  
  	/* TODO: automatic scroll down on a page that's re-opened	
		else if (request.scrollDown != 0) {
			setTimeout(function() {
				chrome.tabs.executeScript(
					null, {file: '/js/scroll.js', runAt: "document_start"}, function() {});
				chrome.runtime.sendMessage({down: request.scrollDown}, function() {});
			  }, 5000);
		}
		*/
   });

chrome.commands.onCommand.addListener(function(command) {
  // Call 'update' with an empty properties object to get access to the current
  // tab (given to us in the callback function).
  chrome.tabs.update({}, function(tab) {
   if (command == 'add-importance-1') add(1);
   else if (command == 'add-importance-2') add(2);
   // else if (command == 'add-importance-3') add(3);
	 else if (command == 'open') open();
  });
});

// inform all content scripts that there's been a change. TODO: inform visual as well (when I work on the new tab page)
// Kind of janky way to send the annotation
function changed(annotation) {
  var db1 = SavedInfo.db().filter({importance:1}).get();
  var db2 = SavedInfo.db().filter({importance:2}).get();
  chrome.tabs.query({}, function(tabs) {
    tabs.forEach(function(tab) {
      chrome.tabs.sendMessage(tab.id, {updated: [db1,db2,annotation]});
    });
  });
}

// user marks tab as "for later"
function add(importance) {
  var tab = {};
  chrome.tabs.query({currentWindow: true, active: true}, function(tabs) {
    var chromeTab = tabs[0];

    tab.time = Date.now();
    tab.timeElapsed = 0;
    tab.loc = SavedInfo.db().filter({importance:importance}).get().length;

    tab.tabId = chromeTab.id;
    tab.favicon = chromeTab.favIconUrl;

    var ttl = chromeTab.title;
    if (ttl.length == 0) ttl = prompt("Please name this page","Untitled");
    tab.title = ttl;

    tab.url = chromeTab.url;

    tab.note = "";  
    tab.color = "rgba(219,217,219,1)";  
      
    tab.importance = importance;

    tab.depth = window.scrollY;
    tab.height = window.innerHeight;
    console.log("My Depth: " + tab.depth);
    console.log("Total Depth: " + document.body.clientHeight);

    // for the drag-and-drop list (could be adapted for 2D manipulation)
    tab.position = SavedInfo.db().count();

    // will be able to "favorite" tabs
    tab.favorite = false;

    // is it a reference tab?
    tab.ref = false;

    //TODO: TASK DB, then get the right task. Where do I record the current task? I'll have to send a message?
    tab.task = "";

    // add to DB.
    var annotation = SavedInfo.db().get()[0].annotation;
    SavedInfo.db.insert(tab).callback(changed(annotation));
  });
    
	// Originally was using a context script here to get page depth information and user highlights on page
  /* chrome.tabs.executeScript(
		null, {file: '/vendor/taffydb/taffy-min.js', runAt: "document_start"}, function() {
		chrome.tabs.executeScript(
		null, {file: '/vendor/underscore/underscore-min.js', runAt: "document_start"}, function() {
		chrome.tabs.executeScript(
		null, {file: '/js/trackAPI.js', runAt: "document_start"}, function() {
		chrome.tabs.executeScript(
		null, {file: '/js/content/content.js', runAt: "document_start"}, function() {
		chrome.tabs.query({'currentWindow': true, 'active': true}, function(tabs) {
			activeId = tabs[0].id;
    	// chrome.tabs.remove(activeId);
	  });});});});}); 
  */
}

function open() {
	console.log('triggered');
	// Opens or closes the sidebar in the current page.
	chrome.tabs.executeScript(null, {file: '/js/content/openclose.js', runAt: "document_start"});
}

// Max at 9 tabs
chrome.tabs.onCreated.addListener(function(tab) {
	chrome.tabs.query({currentWindow: true}, function(tabs) {
		if (tabs.length > 9) {
			alert("Too many tabs!");
			chrome.tabs.remove(tab.id, function() {});
		}
	});
});
