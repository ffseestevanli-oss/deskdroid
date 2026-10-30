# protocol.h is copied next to these files from native/nativedesk.
target_sources(kwin PRIVATE
    nativedesk_backend.cpp
)
target_link_libraries(kwin PRIVATE android)
