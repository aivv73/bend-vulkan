#version 450
layout(set=0,binding=3) uniform Values { vec4 value; } values[2];
void main() {
    vec2 positions[3] = vec2[3](vec2(-1,-1),vec2(3,-1),vec2(-1,3));
    gl_Position = vec4(positions[gl_VertexIndex], values[0].value.x, 1);
}
