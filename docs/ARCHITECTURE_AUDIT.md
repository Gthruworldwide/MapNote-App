# MapNote Architecture Audit

## EDITION STRUCTURE

### Current State
- Single Flutter project mixing AutoMotion and Work Edition features
- No clear edition boundaries in code, dependencies, or build configuration
- AutoMotion features present throughout the codebase

### Required Structure

```text
MAPNOTE CORE
    │
├── WORK EDITION          (NO AutoMotion)
│   • Saved Places/Stations
│   • Station database
│   • Station proposals
│   • Firebase Authentication
│   • Firebase/Firestore station functionality
│   • Admin functionality
│   • Google Drive backup/sync (as applicable)
│   • Local-first data
│   • Security/Vault
│   • Search
│   • Smart Paste
│   • Map functionality
│   • Sharing/import/export
│   • Work-related station management
│   • NO AutoMotion functionality
│   • NO vehicle tracking
│   • NO driving quality
│   • NO speed tracking
│   • NO background automotive GPS tracking
│   • NO activity recognition required only by AutoMotion
│   • NO automotive sensors
│   • NO AutoMotion analytics
│   • NO AutoMotion-specific permissions
│   • NO AutoMotion-specific services
│
└── AUTOMOTION EDITION    (Full features)
    • Everything in Work Edition
    • AutoMotion
    • Vehicle tracking
    • Driving quality
    • Speed tracking
    • Background automotive GPS tracking
    • Activity recognition
    • Automotive sensors
    • AutoMotion analytics
    • AutoMotion battery sampling
    • Automotive-specific permissions
```

### Edition Separation Mechanism
- Compile-time configuration: `MAPNOTE_EDITION=work` or `MAPNOTE_EDITION=automotion`
- Build-time feature flags
- Centralized edition capabilities (`EditionCapabilities`)
- Conditional initialization based on edition
- Separate CI/CD jobs for each edition

### Shared Core
- MapNote Core functionality that both editions reuse
- Must not contain AutoMotion-specific code
- Must not depend on AutoMotion services
- Must not initialize AutoMotion services at startup