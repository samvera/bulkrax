$( document ).on('turbolinks:load ready', function() {
  
  $( "button#entry_error" ).click(function() {
    $( "#error_trace" ).toggle();
  });

  $( "button#raw_button" ).click(function() {
    $( "#raw_metadata" ).toggle();
  });

  $( "button#parsed_button" ).click(function() {
    $( "#parsed_metadata" ).toggle();
  });
  
})
