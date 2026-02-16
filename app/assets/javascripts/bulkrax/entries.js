function setupButtonToggles() {
  $("button#entry_error").click(function() {
    $("#error_trace").toggle();
  });

  $("button#raw_button").click(function() {
    $("#raw_metadata").toggle();
  });

  $("button#parsed_button").click(function() {
    $("#parsed_metadata").toggle();
  });
}

// Use Turbolinks if available, fallback to Turbo if available, fallback to vanilla JS if needed.
if (typeof Turbolinks !== 'undefined' && Turbolinks !== null) {
  $(document).on('turbolinks:load ready', setupButtonToggles());
} else if (typeof Turbo !== 'undefined') {
  $(document).on('turbo:load ready', setupButtonToggles());
} else {
  $(document).on('DOMContentLoaded', setupButtonToggles());
}
