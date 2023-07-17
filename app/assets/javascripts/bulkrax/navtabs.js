// enables the tabs in the importers/exporters pages.
$(document).ready(function() {
  $('.nav-tabs a').click(function (e) {
    e.preventDefault();
    $(this).tab('show');
  });
});