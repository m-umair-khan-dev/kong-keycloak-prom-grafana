# NextGCloud Rebranding Changelog

## Overview

Document summarizes all changes made to rebrand Kong Manager OSS to **Next G Cloud Manager**, matching the [Next G Cloud](https://www.nextgcloud.com/) theme and identity.

The NextGCloud site uses a **purple/indigo** color palette (`#7C3AED`, `#6366F1`, `#A855F7`) with dark navy text (`#1E1B4B`), replacing Kong's original **blue/green** gradient (`#1155CB` → `#1DB57C`).

---

## 1. Page Title & Metadata

| File | Change |
|------|--------|
| `index.html` | Title changed from `Kong Manager OSS` → `Next G Cloud Manager` |

```html
<!-- Before -->
<title>Kong Manager OSS</title>

<!-- After -->
<title>Next G Cloud Manager</title>
```

> **Note:** `public/favicon.ico` should be replaced with a NextGCloud favicon file manually.

---

## 2. Logo Files

### `src/assets/logo.svg`
Replaced entirely with NextGCloud branded logo using purple/indigo gradient colors.

**Gradient colors changed:**
- Before: `#1155CB` → `#1DB57C` (blue to green)
- After: `#7C3AED` → `#6366F1` (purple to indigo)

### `src/assets/kong-text-black.svg`
Replaced with "Next G Cloud" text in dark navy (`#1E1B4B`).

### `src/components/NavbarLogo.vue`
```html
<!-- Before -->
<img src="@/assets/logo.svg?external" alt="Kong Manager Logo">

<!-- After -->
<img src="@/assets/logo.svg?external" alt="Next G Cloud Logo">
```

---

## 3. Color Theme Changes

### 3.1 Gradient Colors — `src/components/KonnectCTA.vue`

```scss
/* Before */
.konnect-gradient {
  background: linear-gradient(92.35deg, #003592 -0.87%, #5151FF 99.68%);
}

/* After */
.konnect-gradient {
  background: linear-gradient(92.35deg, #7C3AED -0.87%, #6366F1 99.68%);
}
```

### 3.2 Link Colors — `src/styles/typography.scss`

```scss
/* Before */
a {
  color: $kui-color-text-primary-strong;
  text-decoration: none;
}

/* After */
a {
  color: #7C3AED;
  text-decoration: none;

  &:hover {
    color: #6D28D9;
  }
}
```

### 3.3 Background Color — `src/styles/reboot.scss`

```scss
/* Before */
body {
  background-color: #fff;
}

/* After */
body {
  background-color: #FAFAFE;
}
```

### 3.4 Sidebar & App Layout — `src/App.vue`

Added `:deep()` CSS overrides for sidebar theming:

```scss
/* NextGCloud sidebar color overrides */
:deep(.kong-ui-app-sidebar) {
  background-color: #1E1B4B !important;
}

:deep(.kong-ui-app-sidebar .sidebar-item-primary) {
  &:hover {
    background-color: rgba(124, 58, 237, 0.2) !important;
  }
  
  &.router-link-active,
  &.active {
    background-color: #7C3AED !important;
  }
}

:deep(.kong-ui-app-navbar) {
  background-color: #1E1B4B !important;
}
```

---

## 4. Design Token Overrides

### New File: `src/styles/nextgcloud-overrides.scss`

Created centralized theme override file with CSS custom properties:

```scss
@use "sass:color";

// NextGCloud Color Palette
$nextgcloud-primary-purple: #7C3AED;
$nextgcloud-indigo: #6366F1;
$nextgcloud-light-purple: #A855F7;
$nextgcloud-dark-navy: #1E1B4B;
$nextgcloud-darker-purple: #6D28D9;
$nextgcloud-background: #FAFAFE;

// Override Kong design tokens via CSS custom properties
:root {
  --kui-color-text-primary: #{$nextgcloud-primary-purple};
  --kui-color-text-primary-strong: #{$nextgcloud-darker-purple};
  --kui-color-text-primary-stronger: #5B21B6;
  --kui-color-text-primary-strongest: #4C1D95;
  --kui-color-background-primary: #{$nextgcloud-primary-purple};
  --kui-color-background-primary-weak: #{$nextgcloud-light-purple};
  --kui-color-background-primary-strong: #{$nextgcloud-darker-purple};
  --kui-color-border-primary: #{$nextgcloud-primary-purple};
  --kui-color-border-primary-strong: #{$nextgcloud-darker-purple};
}
```

### Updated: `src/styles/index.ts`

Added import for the new override file:

```typescript
// ... existing imports ...
import './nextgcloud-overrides.scss'
```

---

## 5. Kong-Specific Branding Text

### `src/components/MakeAWish.vue`

```typescript
// Before
const mailToUrl = computed(() => `mailto:wish@konghq.com?subject=${t('wish.subject', { title: `${route.meta.title} | Kong Manager OSS@${infoStore.kongVersion}` })}`)

// After
const mailToUrl = computed(() => `mailto:contact@nextgcloud.com?subject=${t('wish.subject', { title: `${route.meta.title} | Next G Cloud Manager@${infoStore.kongVersion}` })}`)
```

### `src/components/KonnectCTA.vue`

- Removed Kong text image reference
- Updated CTA link:

```typescript
// Before
const link = 'https://konghq.com/products/kong-konnect/register?utm_medium=product&utm_source=canopy-ui&utm_campaign=gateway-konnect&utm_content=instance-home'

// After
const link = 'https://www.nextgcloud.com/register'
```

### `src/App.vue`

Removed GithubStar component:

```vue
<!-- Before -->
<template #navbar-right>
  <GithubStar url="https://github.com/kong/kong" />
</template>

<!-- After -->
<!-- Removed entirely -->
```

Also removed the import:
```typescript
// Removed
import { GithubStar } from '@kong-ui-public/misc-widgets'
```

### `src/locales/en.json`

Updated all Kong/Konnect references:

```json
// Before
"konnect-cta": {
  "name": "Konnect",
  "description": "The easiest way to get started with Kong Gateway.",
  "feature.1": "Simplify Gateway operations with Konnect's SaaS control plane",
  "feature.4": "Streamline Kong Gateway upgrades"
}

// After
"konnect-cta": {
  "name": "Next G Cloud",
  "description": "The easiest way to get started with Next G Cloud.",
  "feature.1": "Simplify API Gateway operations with cloud-native control plane",
  "feature.4": "Streamline API Gateway upgrades"
}
```

```json
// Before
"resource": {
  "start": {
    "description": "New to Kong? Get started with the basics."
  },
  "plugin": {
    "description": "Extend Kong Gateway with powerful plugins."
  },
  "discuss": {
    "title": "Kong Nation",
    "description": "Discuss Kong with others."
  }
}

// After
"resource": {
  "start": {
    "description": "New to Next G Cloud? Get started with the basics."
  },
  "plugin": {
    "description": "Extend the API Gateway with powerful plugins."
  },
  "discuss": {
    "title": "Community",
    "description": "Discuss Next G Cloud with others."
  }
}
```

---

## 6. Files Summary

### Files Modified

| # | File | Changes |
|---|------|---------|
| 1 | `index.html` | Title updated |
| 2 | `src/assets/logo.svg` | Replaced with NextGCloud logo (purple/indigo gradient) |
| 3 | `src/assets/kong-text-black.svg` | Replaced with "Next G Cloud" text |
| 4 | `src/components/NavbarLogo.vue` | Alt text updated |
| 5 | `src/components/KonnectCTA.vue` | Gradient colors, CTA link, removed Kong image |
| 6 | `src/components/MakeAWish.vue` | Email and product name updated |
| 7 | `src/App.vue` | Removed GithubStar, added sidebar color overrides |
| 8 | `src/styles/typography.scss` | Link colors changed to purple |
| 9 | `src/styles/reboot.scss` | Body background changed to #FAFAFE |
| 10 | `src/styles/index.ts` | Added nextgcloud-overrides.scss import |
| 11 | `src/locales/en.json` | All Kong/Konnect text strings updated |

### New Files Created

| # | File | Purpose |
|---|------|---------|
| 1 | `src/styles/nextgcloud-overrides.scss` | Central theme color overrides (buttons, links, focus states, CSS custom properties) |

### Files to Replace Manually

| # | File | Action |
|---|------|--------|
| 1 | `public/favicon.ico` | Replace with NextGCloud favicon |

---

## 7. NextGCloud Color Palette Reference

| Color | Hex | Usage |
|-------|-----|-------|
| Primary Purple | `#7C3AED` | Primary buttons, links, accents, active states |
| Indigo | `#6366F1` | Gradient end, secondary accent |
| Light Purple | `#A855F7` | Highlights, weak backgrounds |
| Dark Navy | `#1E1B4B` | Sidebar background, navbar, headings |
| Darker Purple | `#6D28D9` | Hover states, strong text |
| Background | `#FAFAFE` | Page background (cool tint) |
| White | `#FFFFFF` | Cards, content areas |

---

Created by Umair Khan & M. Usman Shariff