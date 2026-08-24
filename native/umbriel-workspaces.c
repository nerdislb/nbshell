#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>
#include "ext-workspace-v1-client-protocol.h"

#define MAX_OUTPUTS 16
#define MAX_GROUPS 16
#define MAX_WORKSPACES 128

struct output_state { struct wl_output *handle; char name[128]; };
struct group_state { struct ext_workspace_group_handle_v1 *handle; struct wl_output *output; bool removed; };
struct workspace_state {
    struct ext_workspace_handle_v1 *handle;
    struct group_state *group;
    char id[256];
    char name[256];
    uint32_t coordinate;
    bool coordinate_seen;
    uint32_t state;
    bool removed;
};

static struct wl_display *display;
static struct ext_workspace_manager_v1 *manager;
static struct output_state outputs[MAX_OUTPUTS];
static struct group_state groups[MAX_GROUPS];
static struct workspace_state workspaces[MAX_WORKSPACES];
static size_t output_count, group_count, workspace_count;

static void copy_text(char *target, size_t size, const char *value) {
    snprintf(target, size, "%s", value ? value : "");
}

static void json_text(const char *value) {
    putchar('"');
    for (const unsigned char *p = (const unsigned char *)(value ? value : ""); *p; ++p) {
        switch (*p) {
        case '"': fputs("\\\"", stdout); break;
        case '\\': fputs("\\\\", stdout); break;
        case '\n': fputs("\\n", stdout); break;
        case '\r': fputs("\\r", stdout); break;
        case '\t': fputs("\\t", stdout); break;
        default:
            if (*p < 0x20) printf("\\u%04x", *p); else putchar(*p);
        }
    }
    putchar('"');
}

static const char *output_name(struct wl_output *handle) {
    for (size_t i = 0; i < output_count; ++i)
        if (outputs[i].handle == handle) return outputs[i].name;
    return "";
}

static struct workspace_state *find_workspace(struct ext_workspace_handle_v1 *handle) {
    for (size_t i = 0; i < workspace_count; ++i)
        if (workspaces[i].handle == handle) return &workspaces[i];
    return NULL;
}

static void emit_state(void) {
    fputs("{\"event\":\"workspaces\",\"data\":[", stdout);
    bool first = true;
    for (size_t i = 0; i < workspace_count; ++i) {
        struct workspace_state *workspace = &workspaces[i];
        if (workspace->removed || (workspace->state & EXT_WORKSPACE_HANDLE_V1_STATE_HIDDEN)) continue;
        if (!first) putchar(',');
        first = false;
        const char *id = workspace->id[0] ? workspace->id : workspace->name;
        unsigned int idx = 0;
        if (workspace->name[0]) {
            char *end = NULL;
            unsigned long parsed = strtoul(workspace->name, &end, 10);
            if (end && !*end && parsed > 0 && parsed <= UINT32_MAX) idx = (unsigned int)parsed;
        }
        if (!idx && workspace->coordinate_seen) idx = workspace->coordinate + 1;
        if (!idx) idx = (unsigned int)i + 1;
        fputs("{\"id\":", stdout); json_text(id);
        fputs(",\"name\":", stdout); json_text(workspace->name);
        fputs(",\"output\":", stdout); json_text(workspace->group ? output_name(workspace->group->output) : "");
        printf(",\"idx\":%u,\"is_active\":%s,\"is_focused\":%s,\"is_urgent\":%s}",
            idx,
            workspace->state & EXT_WORKSPACE_HANDLE_V1_STATE_ACTIVE ? "true" : "false",
            workspace->state & EXT_WORKSPACE_HANDLE_V1_STATE_ACTIVE ? "true" : "false",
            workspace->state & EXT_WORKSPACE_HANDLE_V1_STATE_URGENT ? "true" : "false");
    }
    fputs("]}\n", stdout);
    fflush(stdout);
}

static void output_geometry(void *data, struct wl_output *output, int32_t x, int32_t y, int32_t pw, int32_t ph,
                            int32_t subpixel, const char *make, const char *model, int32_t transform) {
    (void)data; (void)output; (void)x; (void)y; (void)pw; (void)ph; (void)subpixel; (void)make; (void)model; (void)transform;
}
static void output_mode(void *data, struct wl_output *output, uint32_t flags, int32_t width, int32_t height, int32_t refresh) {
    (void)data; (void)output; (void)flags; (void)width; (void)height; (void)refresh;
}
static void output_done(void *data, struct wl_output *output) { (void)data; (void)output; }
static void output_scale(void *data, struct wl_output *output, int32_t scale) { (void)data; (void)output; (void)scale; }
static void output_name_event(void *data, struct wl_output *output, const char *name) {
    (void)output; copy_text(((struct output_state *)data)->name, 128, name);
}
static void output_description(void *data, struct wl_output *output, const char *description) {
    (void)data; (void)output; (void)description;
}
static const struct wl_output_listener output_listener = {
    .geometry = output_geometry, .mode = output_mode, .done = output_done, .scale = output_scale,
    .name = output_name_event, .description = output_description,
};

static void group_capabilities(void *data, struct ext_workspace_group_handle_v1 *group, uint32_t capabilities) {
    (void)data; (void)group; (void)capabilities;
}
static void group_output_enter(void *data, struct ext_workspace_group_handle_v1 *group, struct wl_output *output) {
    (void)group; ((struct group_state *)data)->output = output;
}
static void group_output_leave(void *data, struct ext_workspace_group_handle_v1 *group, struct wl_output *output) {
    (void)group; if (((struct group_state *)data)->output == output) ((struct group_state *)data)->output = NULL;
}
static void group_workspace_enter(void *data, struct ext_workspace_group_handle_v1 *group,
                                  struct ext_workspace_handle_v1 *workspace) {
    (void)group; struct workspace_state *state = find_workspace(workspace); if (state) state->group = data;
}
static void group_workspace_leave(void *data, struct ext_workspace_group_handle_v1 *group,
                                  struct ext_workspace_handle_v1 *workspace) {
    (void)group; struct workspace_state *state = find_workspace(workspace); if (state && state->group == data) state->group = NULL;
}
static void group_removed(void *data, struct ext_workspace_group_handle_v1 *group) {
    (void)group; ((struct group_state *)data)->removed = true;
}
static const struct ext_workspace_group_handle_v1_listener group_listener = {
    .capabilities = group_capabilities, .output_enter = group_output_enter, .output_leave = group_output_leave,
    .workspace_enter = group_workspace_enter, .workspace_leave = group_workspace_leave, .removed = group_removed,
};

static void workspace_id(void *data, struct ext_workspace_handle_v1 *workspace, const char *id) {
    (void)workspace; copy_text(((struct workspace_state *)data)->id, 256, id);
}
static void workspace_name(void *data, struct ext_workspace_handle_v1 *workspace, const char *name) {
    (void)workspace; copy_text(((struct workspace_state *)data)->name, 256, name);
}
static void workspace_coordinates(void *data, struct ext_workspace_handle_v1 *workspace, struct wl_array *coordinates) {
    (void)workspace; struct workspace_state *state = data; state->coordinate = 0;
    state->coordinate_seen = coordinates && coordinates->size >= sizeof(uint32_t);
    if (state->coordinate_seen) state->coordinate = *(uint32_t *)coordinates->data;
}
static void workspace_state_event(void *data, struct ext_workspace_handle_v1 *workspace, uint32_t state) {
    (void)workspace; ((struct workspace_state *)data)->state = state;
}
static void workspace_capabilities(void *data, struct ext_workspace_handle_v1 *workspace, uint32_t capabilities) {
    (void)data; (void)workspace; (void)capabilities;
}
static void workspace_removed(void *data, struct ext_workspace_handle_v1 *workspace) {
    (void)workspace; ((struct workspace_state *)data)->removed = true;
}
static const struct ext_workspace_handle_v1_listener workspace_listener = {
    .id = workspace_id, .name = workspace_name, .coordinates = workspace_coordinates,
    .state = workspace_state_event, .capabilities = workspace_capabilities, .removed = workspace_removed,
};

static void manager_group(void *data, struct ext_workspace_manager_v1 *manager_handle,
                          struct ext_workspace_group_handle_v1 *handle) {
    (void)data; (void)manager_handle; if (group_count >= MAX_GROUPS) return;
    struct group_state *state = &groups[group_count++]; state->handle = handle;
    ext_workspace_group_handle_v1_add_listener(handle, &group_listener, state);
}
static void manager_workspace(void *data, struct ext_workspace_manager_v1 *manager_handle,
                              struct ext_workspace_handle_v1 *handle) {
    (void)data; (void)manager_handle; if (workspace_count >= MAX_WORKSPACES) return;
    struct workspace_state *state = &workspaces[workspace_count++]; state->handle = handle;
    ext_workspace_handle_v1_add_listener(handle, &workspace_listener, state);
}
static void manager_done(void *data, struct ext_workspace_manager_v1 *manager_handle) {
    (void)data; (void)manager_handle; emit_state();
}
static void manager_finished(void *data, struct ext_workspace_manager_v1 *manager_handle) {
    (void)data; (void)manager_handle; exit(0);
}
static const struct ext_workspace_manager_v1_listener manager_listener = {
    .workspace_group = manager_group, .workspace = manager_workspace, .done = manager_done, .finished = manager_finished,
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t version) {
    (void)data;
    if (!strcmp(interface, ext_workspace_manager_v1_interface.name)) {
        manager = wl_registry_bind(registry, name, &ext_workspace_manager_v1_interface, 1);
        ext_workspace_manager_v1_add_listener(manager, &manager_listener, NULL);
    } else if (!strcmp(interface, wl_output_interface.name) && output_count < MAX_OUTPUTS) {
        uint32_t bind_version = version < 4 ? version : 4;
        struct output_state *state = &outputs[output_count++];
        state->handle = wl_registry_bind(registry, name, &wl_output_interface, bind_version);
        wl_output_add_listener(state->handle, &output_listener, state);
    }
}
static void registry_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data; (void)registry; (void)name;
}
static const struct wl_registry_listener registry_listener = { .global = registry_global, .global_remove = registry_remove };

int main(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    display = wl_display_connect(NULL);
    if (!display) { fputs("unable to connect to Wayland display\n", stderr); return 1; }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !manager) {
        fputs("ext-workspace-v1 is not available\n", stderr); return 2;
    }
    while (wl_display_dispatch(display) >= 0) {}
    return 0;
}
