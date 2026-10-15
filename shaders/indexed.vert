#version 450
layout(location=0) in vec3 position;
layout(location=1) in vec3 color;
layout(push_constant) uniform Camera { mat4 view_projection; } camera;
layout(location=0) flat out vec3 vertex_color;
void main() {
    gl_Position = camera.view_projection * vec4(position, 1.0);
    vertex_color = color;
}
