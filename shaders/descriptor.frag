#version 450
layout(set=0,binding=3) uniform Values { vec4 value; } values[2];
layout(set=1,binding=9) uniform sampler2D depths[2];
layout(location=0) out vec4 output_color;
void main() {
    float a = texture(depths[0], gl_FragCoord.xy / vec2(8,4)).r;
    float b = texture(depths[1], gl_FragCoord.xy / vec2(8,4)).r;
    output_color = vec4(values[1].value.y, a, b, 1);
}
