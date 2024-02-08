Blacklight.onLoad(function() {
  if($('#importer-show-table').length) {
    $('#importer-show-table').DataTable( {
      'processing': true,
      'serverSide': true,
      "ajax": window.location.href.replace(/(\/importers\/\d+)/, "$1/entry_table.json"),
      "pageLength": 30,
      "lengthMenu": [[30, 100, 200], [30, 100, 200]],
      "columns": [
        { "data": "identifier" },
        { "data": "id" },
        { "data": "status_message" },
        { "data": "type" },
        { "data": "updated_at" },
        { "data": "errors", "orderable": false },
        { "data": "actions", "orderable": false }
      ],
      "dom": '<"toolbar">frtip',
      initComplete: function () {
        // Add entry class filter
        let select = document.createElement('select');
        select.id = 'entry-filter'
        select.classList.value = 'form-control input-sm'
        select.style.marginRight = '10px'

        let blankOption = new Option('Filter by Entry Class', '');
        select.add(blankOption);
        // Read the options from the footer and add them to the select
        $('#importer-entry-classes').text().split('|').forEach(function (col, i) {
          select.add(new Option(col.trim()))
        })
        document.querySelector('div#importer-show-table_filter').firstChild.prepend(select)

        // Apply listener for user change in value
        select.addEventListener('change', function () {
          var val = select.value;
          this.api()
            .search(val ? val : '', false, false)
            .draw();
        }.bind(this));

        // Add status filter
        select = document.createElement('select');
        select.id = 'entry-filter'
        select.classList.value = 'form-control input-sm'
        select.style.marginRight = '10px'

        blankOption = new Option('Filter by Status', '');
        select.add(blankOption);
        select.add(new Option('Complete'))
        select.add(new Option('Pending'))
        select.add(new Option('Failed'))
        document.querySelector('div#importer-show-table_filter').firstChild.prepend(select)

        // Apply listener for user change in value
        select.addEventListener('change', function () {
          var val = select.value;
          this.api()
            .search(val ? val : '', false, false)
            .draw();
        }.bind(this));

        // Add refresh link
        let refreshLink = document.createElement('a');
        refreshLink.onclick = function() {
          this.api().ajax.reload(null, false)
        }.bind(this)
        refreshLink.classList.value = 'glyphicon glyphicon-refresh'
        refreshLink.style.marginLeft = '10px'
        document.querySelector('div#importer-show-table_filter').firstChild.append(refreshLink)
      }
    } );
  }
})
