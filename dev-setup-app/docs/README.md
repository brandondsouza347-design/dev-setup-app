# Documentation Resources

This folder contains user-facing documentation for Dev_Setup.

## Files

### MAC_INSTALLATION.md
Comprehensive technical installation guide for macOS including:
- Step-by-step installation instructions
- Troubleshooting common issues
- System requirements
- Architecture support details
- Security notes

**Audience:** Technical users, IT administrators

### INSTALLATION_GUIDE.md
Simplified visual installation guide designed for easy conversion to PDF:
- Quick 3-step installation
- Visual layouts with emojis and tables
- Common troubleshooting
- What the app does
- Security & trust information

**Audience:** All users (developers, non-technical staff)

## Converting to PDF

### Option 1: Pandoc (Best Quality)
```bash
# Install pandoc (if not installed)
brew install pandoc

# Convert with styling
pandoc INSTALLATION_GUIDE.md \
  -o "Dev_Setup_Installation_Guide.pdf" \
  --pdf-engine=xelatex \
  -V geometry:margin=1in \
  -V colorlinks=true \
  -V linkcolor=blue \
  -V urlcolor=blue \
  -V toccolor=gray \
  --toc \
  --toc-depth=2
```

### Option 2: Markdown to PDF Online
1. Open https://www.markdowntopdf.com/
2. Upload `INSTALLATION_GUIDE.md`
3. Download the generated PDF

### Option 3: VS Code Extension
1. Install "Markdown PDF" extension in VS Code
2. Open `INSTALLATION_GUIDE.md`
3. Press `Ctrl+Shift+P` (Windows) or `Cmd+Shift+P` (Mac)
4. Type "Markdown PDF: Export (pdf)"
5. Save the generated PDF

### Option 4: GitHub/GitLab Rendering
1. Upload the markdown file to GitHub/GitLab
2. Use browser print → Save as PDF
3. Clean and formatted output

## Distribution

### For End Users
**Recommended:** Include `INSTALLATION_GUIDE.md` in the DMG (bundled automatically during build)

**Alternative:** Convert to PDF and distribute via:
- Email attachments
- Internal wiki/confluence
- SharePoint/Google Drive
- Slack channel pins

### For IT Teams
Send `MAC_INSTALLATION.md` to administrators who need technical details.

## Updating Documentation

When app features change:
1. Update relevant markdown files
2. Regenerate PDFs if distributing separately
3. Rebuild DMG to include updated docs
4. Version documentation (add version number in filename)

## Customization

### Adding Company Branding
Edit the markdown files to add:
- Company logo (as image link)
- Internal URLs (wiki, support, GitLab)
- Slack channels
- IT contact information

Example:
```markdown
## Support
- **IT Helpdesk:** helpdesk@company.com
- **Slack:** #dev-setup-support
- **Wiki:** https://wiki.company.com/dev-setup
```

### Screenshots
To add screenshots to the PDF:
1. Take screenshots of installation steps
2. Save as PNG files in `docs/images/`
3. Reference in markdown:
   ```markdown
   ![Installation Window](images/install-window.png)
   ```
4. Regenerate PDF

## Quick Reference Card

For a printable one-page reference, see the "Installation Quick Reference" section at the top of `INSTALLATION_GUIDE.md`.

To extract just that section:
```bash
# Extract first 100 lines (quick reference)
head -n 100 INSTALLATION_GUIDE.md > QUICK_REFERENCE.md
```

---

*Documentation for Dev_Setup v2.6.3*
