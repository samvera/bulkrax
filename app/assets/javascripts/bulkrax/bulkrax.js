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

  // Initialize the uploader
  $('.fileupload-bulkrax').hyraxUploader({ maxNumberOfFiles: 1 });

  // Function to toggle 'required' attribute based on uploaded files
  function toggleRequiredAttribute() {
    const fileInput = $('#addfiles');
    const uploadedFilesTable = $('.fileupload-bulkrax tbody.files');

    if (uploadedFilesTable.find('tr.template-download').length > 0) {
      // Remove 'required' if there are uploaded files
      fileInput.removeAttr('required');
    } else {
      // Add 'required' if no uploaded files
      fileInput.attr('required', 'required');
    }
  }

  // Check the required attribute when a file is added or removed
  $('#addfiles').on('change', function() {
    toggleRequiredAttribute();
  });

  // Also check when an upload completes or is canceled
  $('.fileupload-bulkrax').on('fileuploadcompleted fileuploaddestroyed', function() {
    toggleRequiredAttribute();
  });

  // Ensure 'required' is only added if there are no files on form reset
  $('#file-upload-cancel-btn').on('click', function() {
    $('#addfiles').attr('required', 'required');
    $('#addfiles').val(''); // Clear file input to ensure 'required' behavior resets
  });

  // Initial check in case files are already uploaded
  toggleRequiredAttribute();
});
