function hideUnhide(field) {
  var allSources = $('body').find('.export-source-option')
  removeRequired(allSources)
  hide(allSources)

  if (field.length > 0) {
    var selectedSource = $('.' + field)
    unhideSelected(selectedSource)
    addRequired(selectedSource)
  }

  if (field === 'collection') {
    initCollectionSearchInputs();
  }
};

function addRequired(selectedSource) {
  selectedSource.addClass('required').attr('required', 'required');
  selectedSource.parent().addClass('required');
}

function removeRequired(allSources) {
  allSources.removeClass('required').removeAttr('required');
  allSources.parent().removeClass('required').removeAttr('required')
};

// hide all export_source
function hide(allSources) {
  allSources.addClass('d-none hidden');
  allSources.find('#exporter_export_source').addClass('.d-none hidden').attr('type', 'd-none hidden');
}

// unhide selected export_source
function unhideSelected(selectedSource) {
  selectedSource.removeClass('d-none hidden').removeAttr('type');
  selectedSource.parent().removeClass('d-none hidden').removeAttr('type');
};

// add the autocomplete javascript
function initCollectionSearchInputs() {
  $('[data-autocomplete]').each((function() {
    var elem = $(this)
    initSelect2(elem, elem.data('autocompleteUrl'))
  }))
}

function initSelect2(element, url) {
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
        };
      },
      results: function(data, page) {
        // parse the results into the format expected by Select2.
        // since we are using custom formatting functions we do not need to alter remote JSON data
        let results = data.map((obj) => {
          return { id: obj.id, text: obj.label[0] };
        })
        return { results: results };
      }
    }
  }).select2('data', null);
}
