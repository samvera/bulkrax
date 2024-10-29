// Global JS file for Bulkrax

$(document).on('turbolinks:load ready', function() {
  // Apply to Importer and Exporter views
  $('button#err_toggle').click(function() {
    $('#error_trace').toggle();
  });
  
  $('button#fm_toggle').click(function() {
    $('#field_mapping').toggle();
  });

  $('#bulkraxItemModal').on('show.bs.modal', function (event) {
    var button = $(event.relatedTarget); // Button that triggered the modal
    var recipient = button.data('entry-id'); // Extract info from data-* attributes

    var modal = $(this);
    modal.find('a').each(function() {
      this.href = this.href.replace(/\d+\?/, recipient + '?');
    });
    return true;
  });
});
