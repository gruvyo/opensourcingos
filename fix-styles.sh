#!/bin/bash

# Update globals.css with proper base text colors
cat > app/globals.css << 'EOF'
@import "tailwindcss";

:root {
  --background: #ffffff;
  --foreground: #171717;
}

html {
  color: var(--foreground);
}

body {
  background: var(--background);
  color: var(--foreground);
  font-family: var(--font-inter), system-ui, -apple-system, sans-serif;
}

/* Ensure form inputs have dark, readable text */
input,
select,
textarea {
  color: #1f2937;
}

input::placeholder,
textarea::placeholder {
  color: #9ca3af;
}

/* Remove dark mode auto-detection that makes text light */
@media (prefers-color-scheme: dark) {
  html {
    color: var(--foreground);
  }
  body {
    background: var(--background);
    color: var(--foreground);
  }
  input,
  select,
  textarea {
    color: #1f2937;
  }
}
EOF

# Clear build cache
rm -rf .next

echo "DONE"
