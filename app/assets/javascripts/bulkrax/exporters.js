jQuery(function() {
  // get the selected export_from option and show the corresponding export_source
  $('.exporter_export_from').change(function() {
    var selectedVal = $('.exporter_export_from option:selected').val();
    hideUnhide(selectedVal);
  });
  // TODO: show the selected export_source option
  // $(document).ready(function() {
    // var selectedOpt = $('.exporter_export_source option:selected');
    // unhideSelected(selectedOpt);
  // });
});

function hideUnhide(field) {
  var allSources = $('body').find('.export-source-option')
  hide(allSources)

  if (field != null) {
    var selectedSource = $('.' + field)
    unhideSelected(selectedSource)
  }

  if (field === 'collection') {
    addAutocomplete();
  }
};

// hide all export_source
function hide(allSources) {
  allSources.addClass('hidden');
  allSources.find('#exporter_export_source').addClass('hidden').attr('type', 'hidden');
}

// unhide selected export_source
function unhideSelected(selectedSource) {
  selectedSource.removeClass('hidden').removeAttr('type');
  selectedSource.parent().removeClass('hidden').removeAttr('type');
};

// add the autocomplete javascript
function addAutocomplete() {
  var Autocomplete = require('hyrax/autocomplete');
  var autocomplete = new Autocomplete()
  $('[data-autocomplete]').each((function() {
    var elem = $(this)
    autocomplete.setup(elem, elem.data('autocomplete'), elem.data('autocompleteUrl'))
  }))
}

// clear selected when focus moves away from the export_from
