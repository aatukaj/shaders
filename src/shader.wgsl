struct DataUniform {
    screen_size: vec2<f32>,
    time: f32,
    
}
@group(0) @binding(0)
var<uniform> data: DataUniform;

struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) tex_coords: vec2<f32>,
};


struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) tex_coords: vec2<f32>,
};

@vertex
fn vs_main(
    model: VertexInput
) -> VertexOutput {
    var out: VertexOutput;
    out.tex_coords = model.tex_coords;;
    out.clip_position = vec4<f32>(model.position, 1.0);
    return out;
}

const MAX_MARCHING_STEPS = 250;
const MIN_DIST = 0.5;
const MAX_DIST = 200.0;
const EPSILON = 0.0001;
const PI = 3.14159274; 
const PI2 = 6.28318548;
const MOD = 16.0;
fn smin(a: f32, b: f32, k: f32) -> f32{
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn sphere_sdf(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn box_sdf(p: vec3<f32>, size: vec3<f32>) -> f32 {
    let q = abs(p) - size;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}
fn round_box_sdf(p: vec3<f32>, size: vec3<f32>, r: f32) -> f32 {
    return box_sdf(p, size) -r;
}

fn cap_cylinder_sdf(p: vec3<f32>, h: f32, r: f32) -> f32 {
    let d = abs(vec2(length(p.xz), p.y)) - vec2(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2(0.0)));
}
fn rotate_x(theta: f32) -> mat3x3<f32> {
    let c = cos(theta);
    let s = sin(theta);
    return mat3x3(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}
fn rotate_z(theta: f32) -> mat3x3<f32> {
    let c = cos(theta);
    let s = sin(theta);
    return mat3x3(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

fn rotate_y(theta: f32) -> mat3x3<f32> {
    let c = cos(theta);
    let s = sin(theta);
    return mat3x3(
        c, 0.0, s, 
        0.0, 1.0, 0.0, 
        -s, 0.0, c
        );
}
fn cyl_cross(p: vec3<f32>, h: f32, r: f32, tile_pos: vec3<f32>) -> f32 {
    let cyls = smin(
        cap_cylinder_sdf(rotate_x(PI / 4.0) * p, h, r), 
        smin(
            cap_cylinder_sdf(p, h, r), 
            cap_cylinder_sdf(p * rotate_z(PI / 4.0), h, r), 
            0.1),
        0.1);
    return cyls;
}
fn floor_to_mul(a: f32, b: f32) -> f32 {
    return floor(a/ b) * b;     
}
fn frame_sdf(z: vec3<f32>) -> f32 {
    let scale = 8.0;
    let edge = 0.5;
    let ext = smin(smin(box_sdf(z, vec3(scale-edge, scale-edge, scale + 1.0)), box_sdf(z, vec3(scale + 1.0, scale-edge, scale-edge)), 0.2), box_sdf(z, vec3(scale-edge, scale + 1.0, scale-edge)), 0.2);
    return max(round_box_sdf(z, vec3(scale, scale, scale), 0.5), -ext);
}
fn meta_sdf(z: vec3<f32>, tile_pos: vec3<f32>) -> f32 {
    let t = data.time + length(tile_pos);
    let s1= sphere_sdf(z + vec3(0.0, sin(t + 0.2) * 2.0, 0.0), 1.5);
    let s2 = sphere_sdf(z + vec3(sin(t)* 2.0, sin(t + tile_pos.x) * 2.0, cos(2.0 * t) * 2.0), 1.5);
    let s3 = sphere_sdf(z - vec3(sin(t + tile_pos.y) * 2.0, sin(t)* 2.0, cos(1.0 * t) * 2.0), 1.5);
    return smin(s1, smin(s2, s3, 0.5), 0.5);
}

fn scene_sdf(p: vec3<f32>) -> f32 {
    let mul = MOD;
    var z : vec3<f32> = fract(p.xyz / mul) * mul - vec3<f32>(mul / 2.0);
    //var z: vec3<f32> = p - vec3<f32>(mul / 2.0); 
    let tile_pos = floor(p / mul);
    
    
    

    return min(frame_sdf(z), meta_sdf(z, tile_pos));
}

fn shortest_distance_to_surface(eye: vec3<f32>, marching_dir: vec3<f32>, start: f32, end: f32) -> f32 {
    var depth : f32 = start;
    var steps: i32;
    for (steps = 0; steps < MAX_MARCHING_STEPS; steps++) {
        let dist = scene_sdf(eye+depth * marching_dir);
        depth += dist;
        if (dist < EPSILON) {
            break;
        }
        
    }
    return depth;
}

fn ray_direction(fov: f32, size: vec2<f32>, position: vec2<f32>) -> vec3<f32> {
    let xy = position - size / 2.0;
    let z = size.y / tan(radians(fov) / 2.0);
    return normalize(vec3<f32>(xy, -z));
}
fn estimate_normal(p: vec3<f32>) -> vec3<f32>{
    return normalize(vec3<f32>(
        scene_sdf(vec3<f32>(p.x + EPSILON, p.y, p.z)) -scene_sdf(vec3<f32>(p.x - EPSILON, p.y, p.z)),
        scene_sdf(vec3<f32>(p.x, p.y + EPSILON, p.z)) -scene_sdf(vec3<f32>(p.x , p.y - EPSILON, p.z)),
        scene_sdf(vec3<f32>(p.x, p.y, p.z + EPSILON)) -scene_sdf(vec3<f32>(p.x , p.y, p.z - EPSILON)),
    ));
}
fn view_matrix(eye: vec3<f32>, center: vec3<f32>, up: vec3<f32>) -> mat3x3<f32> {
    let f = normalize(center - eye);
    let s = normalize(cross(f, up));
    let u = cross(s, f);
    return mat3x3<f32>(s, u, -f);
}

fn min_abs(a: f32, b: f32) -> f32{
    return(smin(a, abs(b), 0.1) * sign(b));
} 

fn camera_pos(time: f32) -> vec3<f32> {
    return vec3(MOD, 0.0, MOD * 0.5 * sin(time)) * rotate_y(time % PI2) * rotate_x(time * 0.2 % PI2) + vec3(cos(time), MOD * time, MOD * time);
}


@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let dir = ray_direction(60.0, data.screen_size, in.clip_position.xy);
    let pos =camera_pos(data.time);
    let offset = -vec3(MOD / 2.0);
    let center = pos + offset;
    let t = data.time;

    let eye = vec3(camera_pos(data.time - 1.0)) + offset;
    let view_to_world = view_matrix(eye, center, vec3<f32>(0.0, 1.0, 0.) * rotate_z(sin(t)));

    let world_dir = view_to_world * dir;

    let dist = shortest_distance_to_surface(eye, world_dir, MIN_DIST, MAX_DIST);
    var col: vec3<f32> = vec3<f32>(0.0, 0.0, 0.0);
    let bg = vec3(max(0.0, 1.0 * sin((t * PI * 1.0) / 60.0 * 170.0)));
    if (dist > MAX_DIST - EPSILON) {
        return vec4<f32>(bg, 1.0);
        
    }
    let p = eye + world_dir * dist;
    let mul = MOD;
    var z : vec3<f32> = fract(p.xyz / mul) * mul - vec3<f32>(mul / 2.0);
    let tile_pos = floor(p / mul);
    let norm = estimate_normal(p);
    if frame_sdf(z) < meta_sdf(z, tile_pos) {
        col = (norm + vec3<f32>(1.0)) / 2. * rotate_x(1.3 * data.time);
    } else {
        col = vec3(0.0, 0.0, 0.0);
    }
    
    return vec4<f32>(mix(col, bg,(dist / MAX_DIST)), 1.0);
}