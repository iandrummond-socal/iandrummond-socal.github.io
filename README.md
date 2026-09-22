# Park Avenue Projects

A single-page, static website for Ian Drummond and Park Ave Projects, LLC. The complete site requires no build process, package manager, backend, or API keys.

## Files

- `index.html`: page content, editorial styling, metadata, and a small appearance toggle.
- `base.css`: accessibility and browser baseline styles.
- `assets/ian-drummond.webp`: optimized portrait.
- `assets/signature.svg`: supplied vector signature, with its view box cropped to the artwork.
- `assets/favicon.svg`: custom architectural monogram.
- `.nojekyll`: included for static hosting.

## Preview locally

Open `index.html` in a browser, keeping the asset folder beside it. Web fonts need an internet connection; fallback fonts keep the page readable without one.

## Publish on GitHub Pages

Put the contents of this package at the root of your chosen repository, so `index.html` is at the top level, not inside another folder. Commit the files to your publishing branch, such as `main`.

In the repository, open **Settings → Pages**. Under **Build and deployment**, choose **Deploy from a branch**, select your branch and **/ (root)**, then choose **Save**, following [GitHub’s publishing-source instructions](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).

Use the live URL displayed in the Pages settings after deployment. All site assets use relative paths, so the same package supports a repository subpath or a domain root.

No domain configuration or `CNAME` file is included. The business email domain has not been assumed to be the website’s confirmed hosting domain.

## Edit the site

- **Copy and links:** edit the HTML in `index.html`.
- **Colors and typography:** edit the CSS variables at the beginning of the inline stylesheet.
- **Portrait:** replace `assets/ian-drummond.webp`, preserving its filename or updating the image path and dimensions.
- **Signature:** replace `assets/signature.svg`.
- **Social sharing:** after confirming your production URL, add an absolute `og:image` URL and a canonical URL to the page head.

## Typography

The utility/navigation font stack requests `Franklin Gothic Medium` first and loads `Libre Franklin` as its web fallback. A Franklin Gothic Medium font file is not bundled; to make that exact typeface appear consistently on every device, supply a properly web-licensed font file and add an `@font-face` rule.

Cormorant Garamond supplies the masthead and display headings; Source Serif 4 supplies the editorial body text. These fonts and Libre Franklin are loaded from Google Fonts.

## Behavior and privacy

The site includes responsive desktop and mobile layouts, a light/dark appearance toggle, keyboard focus styles, a skip link, reduced-motion support, and print styles. Every page visit starts with a white background, regardless of the device’s appearance setting. The appearance selection lasts for the current page visit and does not use cookies or browser storage.

All contact actions use `mailto:` links, including the CV request. There is no contact form, analytics code, visitor tracking, or backend. Font loading makes requests to Google Fonts; fonts can be self-hosted later if desired.

## Contact destinations

- Email: `ian@parkaveprojects.com`
- LinkedIn: `https://www.linkedin.com/in/iandrummond/`
- GitHub: `https://github.com/iandrummond-socal`
- X: `https://x.com/iandrummond`
