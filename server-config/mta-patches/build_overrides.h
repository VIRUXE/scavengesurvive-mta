// Copied over Shared/build_overrides.h before building the patched deathmatch module
// (docs/runbooks/patched-mta-server.md).
//
// MTASA_VERSION_BUILD must equal the build of the server the module goes into (getVersion().sortable on it,
// 1.6.0-9.<build>.0): core checks that the module's GetLibMtaVersion string matches its own exactly and refuses
// to load it otherwise. 24153 is production; the dev box runs 24160.
#undef MTASA_VERSION_TYPE
#undef MTASA_VERSION_BUILD
#define MTASA_VERSION_TYPE  VERSION_TYPE_RELEASE
#define MTASA_VERSION_BUILD 24153
