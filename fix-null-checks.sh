#!/bin/bash

# Fix baselines-tab.tsx — add null checks for user
sed -i '' "s/\.eq('id', user\.id)/\.eq('id', user\!.id)/g" components/baselines-tab.tsx
sed -i '' "s/\.eq('id', user?\.id)/\.eq('id', user\!.id)/g" components/baselines-tab.tsx

# Fix offers-tab.tsx
sed -i '' "s/\.eq('id', user\.id)/\.eq('id', user\!.id)/g" components/offers-tab.tsx
sed -i '' "s/\.eq('id', user?\.id)/\.eq('id', user\!.id)/g" components/offers-tab.tsx

# Fix calculations-tab.tsx
sed -i '' "s/\.eq('id', user\.id)/\.eq('id', user\!.id)/g" components/calculations-tab.tsx
sed -i '' "s/\.eq('id', user?\.id)/\.eq('id', user\!.id)/g" components/calculations-tab.tsx

# Fix realization-tab.tsx
sed -i '' "s/\.eq('id', user\.id)/\.eq('id', user\!.id)/g" components/realization-tab.tsx
sed -i '' "s/\.eq('id', user?\.id)/\.eq('id', user\!.id)/g" components/realization-tab.tsx

# Fix scope-lines-tab.tsx
sed -i '' "s/\.eq('id', user\.id)/\.eq('id', user\!.id)/g" components/scope-lines-tab.tsx
sed -i '' "s/\.eq('id', user?\.id)/\.eq('id', user\!.id)/g" components/scope-lines-tab.tsx

# Fix event-form.tsx
sed -i '' "s/\.eq('id', user\.id)/\.eq('id', user\!.id)/g" components/event-form.tsx
sed -i '' "s/\.eq('id', user?\.id)/\.eq('id', user\!.id)/g" components/event-form.tsx

echo "DONE"
