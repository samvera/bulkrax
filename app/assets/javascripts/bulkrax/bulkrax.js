// Global JS file for Bulkrax

function setupGlobalListeners() {
  console.log("setting up global listeners");
  // Apply to Importer and Exporter views
  $('button#err_toggle').click(function() {
    $('#error_trace').toggle();
  });

  $('button#fm_toggle').click(function() {
    $('#field_mapping').toggle();
  });

  $('#bulkraxItemModal').on('show.bs.modal', function(event) {
    var button = $(event.relatedTarget); // Button that triggered the modal
    var recipient = button.data('entry-id'); // Extract info from data-* attributes
    // If necessary, you could initiate an AJAX request here (and then do the updating in a callback).
    // Update the modal's content. We'll use jQuery here, but you could use a data binding library or other methods instead.
    var modal = $(this);
    modal.find('a').each(function() {
      this.href = this.href.replace(/\d+\?/, recipient + '?');
    });
    return true;
  });
}

// Use Turbolinks if available, fallback to Turbo if available, fallback to vanilla JS if needed.
if (typeof Turbolinks !== 'undefined' && Turbolinks !== null) {
  $(document).on('turbolinks:load ready', setupGlobalListeners());
} else if (typeof Turbo !== 'undefined') {
  $(document).on('turbo:load ready', setupGlobalListeners());
} else {
  $(document).on('ready', setupGlobalListeners());
}
