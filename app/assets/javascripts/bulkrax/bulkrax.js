// Global JS file for Bulkrax

$(document).on('turbolinks:load ready', function() {
  // Apply to Importer and Exporter views
  $('button#err_toggle').click(function() {
    $('#error_trace').toggle();
  });
  $('button#fm_toggle').click(function() {
    $('#field_mapping').toggle();
  });
});
