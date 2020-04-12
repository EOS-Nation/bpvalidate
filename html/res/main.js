// --------------------------------------------------------------------------
// Listeners

document.addEventListener('DOMContentLoaded', function () {

  // ---------- navbar

  var navbarBurgers = Array.prototype.slice.call(document.querySelectorAll('.navbar-burger'), 0);
  if (navbarBurgers.length > 0) {
    runBurgers(navbarBurgers);
  }

  // ---------- scorecard

  var filterItems = Array.prototype.slice.call(document.querySelectorAll('.filter'), 0);
  if (filterItems.length > 0) {
    runFilters();
  }
});

window.addEventListener('popstate', function(e) {
  // handle the back button
  loadQueryParameters();
});

window.addEventListener('load', function(e) {
  // handle page load
  loadQueryParameters();
});

// --------------------------------------------------------------------------
// Functions

function runBurgers(navbarBurgers) {
  navbarBurgers.forEach(function (element) {
    element.addEventListener('click', function () {
      var target = element.dataset.target;
      var $target = document.getElementById(target);
      element.classList.toggle('is-active');
      $target.classList.toggle('is-active');
    });
  });
}

function clickFilter() {
  setQueryParameters();
  runFilters();
}

function setQueryParameters() {
  var filterItems = Array.prototype.slice.call(document.querySelectorAll('.filter'), 0);

  // set the query string to match the checkboxes

  var parameters = new Array;
  filterItems.forEach(function (checkbox) {
    if (checkbox.checked) {
       parameters.push(checkbox.value);
    }
  });

  var query_string = parameters.join(';');
  if (document.location.search != query_string) {
    history.pushState(null, null, '?' + query_string);
  }
}

function runFilters() {
  var filterItems = Array.prototype.slice.call(document.querySelectorAll('.filter'), 0);

  filterData.producers.forEach(function (filter) {
    var element = document.getElementById('bp_' + filter.name);
    var state = 'inline-block';
    filterItems.forEach(function (checkbox) {
      if (checkbox.checked && filter.tags.indexOf(checkbox.value) == -1) {
        state = 'none';
      }
    });
    element.style.display = state;
  });
}

function loadQueryParameters() {
  var xFilterItems = Array.prototype.slice.call(document.querySelectorAll('.filterx'), 0);
  var filterItems = Array.prototype.slice.call(document.querySelectorAll('.filter'), 0);
  var parameters = parseQueryString();

  xFilterItems.forEach(function (checkbox) {
    checkbox.checked = true;
  });

  filterItems.forEach(function (checkbox) {
    if (parameters[checkbox.value]) {
      checkbox.checked = true;
    }
  });

  runFilters();
}

function parseQueryString() {
  var str = window.location.search;
  var objURL = {};

  str.replace(
    new RegExp("([^?=&;]+)(=([^&;]*))?", "g"),
    function($0, $1, $2, $3){
      objURL[$1 + '=' + $3] = true;
    }
  );

  return objURL;
}
