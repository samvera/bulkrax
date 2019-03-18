// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.

function prepBulkrax(event) {
  var refresh_button = $('.refresh-set-source')
  var base_url = $('#importer_parser_fields_base_url')
  var external_set_select = $("#importer_parser_fields_set")
  var initial_base_url = base_url.val()

  // handle refreshing/loading of external setes via button click
  $('body').on('click', '.refresh-set-source', function(e) {
    e.preventDefault()

    handleSourceLoad(refresh_button, base_url, external_set_select)
  })

  // handle refreshing/loading of external sets via blur event for the base_url field
  $('body').on('blur', '#importer_parser_fields_base_url', function(e) {
    e.preventDefault()

    // ensure we don't make another query if the value is the same -- this can be forced by clicking the refresh button
    if (initial_base_url != base_url.val()) {
      handleSourceLoad(refresh_button, base_url, external_set_select)
      initial_base_url = base_url.val()
    }
  })

  // hide and show correct parser fields depending on klass setting
  $('body').on('change', '#importer_parser_klass', function(e) {
    handleParserKlass()
  })
  handleParserKlass()
}

function handleParserKlass(){
  var parser_klass = $("#importer_parser_klass")

  if($('.oai_fields').length > 0) {
    window.oai_fields = $('.oai_fields').detach()
  }
  if($('.cdri_fields').length > 0) {
    window.cdri_fields = $('.cdri_fields').detach()
  }

  if(parser_klass.length > 0) {
    if(parser_klass.val().match(/oai/i)){
      $('.parser_fields').append(window.oai_fields)
    } else if(parser_klass.val().match(/cdri/i)){
      $('.parser_fields').append(window.cdri_fields)
    }
  }

}

function handleSourceLoad(refresh_button, base_url, external_set_select) {
  if (base_url.val() == "") { // ignore empty base_url value
    return
  }

  var initial_button_text = refresh_button.html()

  refresh_button.html('Refreshing...')
  refresh_button.attr('disabled', true)

  $.post('/importers/external_sets', {
    base_url: base_url.val(),
  }, function(res) {
    if (!res.error) {
      genExternalSetOptions(external_set_select, res.sets) // sets is [[name, spec]...]
    } else {
      setError(external_set_select, res.error)
    }

    refresh_button.html(initial_button_text)
    refresh_button.attr('disabled', false)
  })
}

function genExternalSetOptions(selector, sets) {
  out = '<option value="">- Select One -</option>'

  out += sets.map(function(set) {
    return '<option value="'+set[1]+'">'+set[0]+'</option>'
  })

  selector.html(out)
  selector.attr('disabled', false)
}

function setError(selector, error) {
  selector.html('<option value="none">Error - Please enter Base URL and try again</option>')
  selector.attr('disabled', true)
}

$(document).on({'turbolinks:load': prepBulkrax, 'ready': prepBulkrax})
