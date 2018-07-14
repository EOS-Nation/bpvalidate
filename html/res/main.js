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
