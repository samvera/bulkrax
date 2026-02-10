# Bulk Import Stepper - Implementation Guide

This document explains the new v2 bulk import stepper wizard that was created to replace the React-based UI mockup with a Rails-native implementation.

## Overview

The stepper wizard is a 3-step process for bulk importing CSV files and associated media:

1. **Upload & Validate** - Upload CSV/ZIP files and validate structure
2. **Configure Settings** - Set import parameters (admin set, visibility, etc.)
3. **Review & Start** - Review and confirm before starting the import

**Built with Bootstrap 4** - Uses native Bootstrap 4 components (cards, forms, buttons) with custom styling.

## Files Created/Modified

### Views
- **`app/views/bulkrax/importers/new_v2.html.erb`**
  - Main stepper wizard view
  - Contains all 3 steps, success state, and form structure
  - Uses ERB partials and Bootstrap 4 for layout

### JavaScript
- **`app/assets/javascripts/bulkrax/importers_stepper.js`**
  - Complete state management for the wizard
  - Handles file uploads, validation, navigation between steps
  - Implements accordion, tree view, and gauge components
  - AJAX calls for validation
  - Demo mode with mock data for testing

### Styles
- **`app/assets/stylesheets/bulkrax/stepper.scss`**
  - Complete styling for all components
  - Responsive design with mobile breakpoints
  - Color-coded validation states (success/warning/error)
  - Animations and transitions

### Backend
- **`app/controllers/concerns/bulkrax/importer_v2.rb`**
  - `new_v2` - Renders the stepper form
  - `validate_v2` - AJAX endpoint for CSV validation
  - `create_v2` - Processes the final import submission
  - `perform_validation` - Analyzes CSV structure and content

### Routes
- **`config/routes.rb`**
  - Added `POST /importers/v2/validate` for validation endpoint
  - Existing routes for `new_v2` and `create_v2` already in place

## Key Features

### File Upload States

The wizard handles 4 different upload scenarios:

1. **CSV Only** - Just a metadata CSV (files matched from server paths)
2. **ZIP Files Only** - ZIP without CSV (shows warning to upload CSV)
3. **ZIP with CSV** - Single ZIP containing both CSV and files
4. **CSV + ZIP** - Separate CSV and ZIP files

### Validation

The validation process checks:
- CSV headers and structure
- Missing required fields
- Unrecognized/unmapped fields
- Row counts
- Hierarchy (collections, works, file sets)
- File references and missing files
- Import size recommendations

### Import Size Gauge

Visual gauge showing import optimization:
- **Green (0-100)**: Optimal size
- **Yellow (101-500)**: Moderate - consider splitting
- **Red (500+)**: Large - recommend batching

### Components

All components are built with jQuery + Bootstrap 4:

1. **Stepper Header** - Progress indicator with 3 steps
2. **Accordion** - Collapsible cards for validation results
3. **Tree View** - Hierarchical display of collections/works
4. **Visibility Cards** - Visual selection for access controls
5. **File Rows** - File display with icons and verification badges
6. **Summary Cards** - Count displays for collections/works/filesets

## Testing

### Demo Mode

The stepper includes a demo mode for testing without real files:

1. **Double-click** the upload zone to show demo scenarios
2. Select from 4 pre-configured scenarios
3. Validation uses mock data automatically
4. All UI features are testable

### Real File Testing

1. Upload actual CSV or ZIP files
2. Validation calls the backend endpoint
3. Form submission creates real import jobs

## Usage

### For Users

1. Navigate to Importers index
2. Click "New Import (V2)" button
3. Follow the 3-step wizard:
   - Upload files and validate
   - Configure import settings
   - Review and start import
4. Monitor progress in import queue

### For Developers

#### Customizing Validation

Edit the `perform_validation` method in `importer_v2.rb` to add custom validation logic:

```ruby
def perform_validation(importer, file)
  parser = importer.parser

  # Add custom validation here
  custom_errors = check_custom_rules(parser)

  # Return validation response
  { ... }
end
```

#### Adding New Steps

1. Add step HTML to `new_v2.html.erb`
2. Update stepper header with new step
3. Add navigation logic in JavaScript
4. Update `updateStepperUI()` function

#### Styling Customization

All styles are in `stepper.scss`. Key variables:

```scss
// Colors
$primary: #337ab7;
$success: #5cb85c;
$warning: #ffc107;
$danger: #dc3545;

// Modify gauge colors
.gauge-segment-optimal { background: #c3e6cb; }
.gauge-segment-moderate { background: #ffeaa7; }
.gauge-segment-large { background: #f5c6cb; }
```

## Accessibility

- Semantic HTML with proper ARIA labels
- Keyboard navigation support
- Color contrast ratios meet WCAG AA standards
- Screen reader friendly labels and hints

## Browser Support

- Chrome/Edge (latest 2 versions)
- Firefox (latest 2 versions)
- Safari (latest 2 versions)
- Mobile browsers (iOS Safari, Chrome Android)

## Performance

- Lazy loading of validation results
- Debounced file input handling
- Minimal DOM manipulation
- CSS transitions instead of JavaScript animations
- Asset pipeline compilation and minification

## Future Enhancements

Potential improvements:

1. Real-time progress updates during validation
2. Drag-and-drop file reordering
3. Inline CSV editor for quick fixes
4. Save draft imports for later
5. Bulk import templates
6. Enhanced error messages with suggested fixes
7. File preview before import
8. Duplicate detection

## Troubleshooting

### Assets Not Loading

```bash
# Precompile assets
rake assets:precompile
```

### JavaScript Not Working

- Check browser console for errors
- Verify jQuery is loaded
- Check Turbolinks compatibility

### Validation Fails

- Check server logs for backend errors
- Verify file upload size limits
- Ensure CSV parser is configured correctly

### Styling Issues

- Clear browser cache
- Check for CSS conflicts with existing styles
- Verify Bootstrap 4 is loaded

## Migration from Old Form

The old importer form is still available at `/importers/new`. To fully migrate:

1. Test v2 thoroughly with various file types
2. Train users on new interface
3. Consider deprecating old form
4. Update documentation and help text

## Support

For issues or questions:
- Check application logs
- Review validation error messages
- Consult this documentation
- Open issue in project repository
