jQuery(function() {
  // show the selected export_source option
  // TODO: double check if jQuery(function) IS document.ready
  $(document).ready(function() {
    var selectedVal = $('.exporter_export_from option:selected').val();
    hideUnhide(selectedVal);

    // if (selectedVal == 'collection') {
      // $('#exporter_export_source_collection').val() // TODO: pass @collection.id
    // }
  });

  // get the selected export_from option and show the corresponding export_source
  $('.exporter_export_from').change(function() {
    var selectedVal = $('.exporter_export_from option:selected').val();
    hideUnhide(selectedVal);
  });
});

function hideUnhide(field) {
  var allSources = $('body').find('.export-source-option')
  hide(allSources)

  if (field.length > 0) {
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
  $('[data-autocomplete]').each((function() {
    var elem = $(this)
    initUI(elem, elem.data('autocompleteUrl'))
  }))
}

function initUI(element, url) { // TODO: rename func
  element.select2({
    minimumInputLength: 2,
    initSelection : (row, callback) => {
      var data = {id: row.val(), text: row.val()};
      callback(data);
    },
    ajax: { // instead of writing the function to execute the request we use Select2's convenient helper
      url: url,
      dataType: 'json',
      data: (term, page) => {
        return {
          q: term // search term
          // id: this.excludeWorkId // Exclude this work // TODO: determine if this is needed
        };
      },
      results: processResults
    }
  }).select2('data', null);
}

// parse the results into the format expected by Select2.
// since we are using custom formatting functions we do not need to alter remote JSON data
function processResults(data, page) {
  let results = data.map((obj) => {
    return { id: obj.id, text: obj.label[0] };
  })
  return { results: results };
}
