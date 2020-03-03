$( document ).on('turbolinks:load ready', function() {
  $( "button#entry_error" ).click(function() {
    $( "#error_trace" ).toggle();
  });
})
