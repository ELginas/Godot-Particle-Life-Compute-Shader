#[compute]
#version 450
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

struct MyVec2 { vec2 v; };

// Image buffers with encoded particle data
layout(rgba32f, set = 0, binding = 0) uniform restrict image2D input_particles; // R=pos.x, G=pos.y, B=vel.x, A=vel.y
layout(rgba32f, set = 1, binding = 0) uniform restrict image2D output_particles;

// Input
layout(set = 0, binding = 1, std430) buffer InSpeciesBuffer { int data[]; }   in_species_buffer;

// Interaction matrix (species_count x species_count)
layout(set = 0, binding = 2, std430) readonly buffer MatrixBuffer {
    float data[];
} interaction_matrix;

// Parameters
layout(push_constant, std430) uniform Params {
    float dt;
	float compute_texture_size;
    float damping;
    float point_count;
    float species_count;
    float interaction_radius;
	float collision_radius;
	float collision_strength;
	float border_style;
	float border_scale;
	float image_size;
	float center_attraction;
	float force_softening;
	float max_force;
	float max_velocity;
} params;

// Apply a softened and capped force
float apply_force(float f, float dist, float softening, float max_force) {
    float softened_dist = sqrt(dist * dist + softening * softening);
    float force_mag = f / softened_dist;
	
    return clamp(force_mag, -max_force, max_force);
}

// Simple 2D hash to make a pseudo-random direction from particle IDs
vec2 random_dir(uint a, uint b) {
    uint seed = a * 1664525u + b * 1013904223u; // LCG mix
    float ang = float(seed % 6283u) * 0.001f;   // ~0 to ~2pi
    return vec2(cos(ang), sin(ang));
}

// Applies border constraints based on params.border_style and border_scale
void apply_border(inout vec2 pos, inout vec2 vel) {
    ivec2 size = ivec2(params.image_size);
	
    vec2 half_bounds = vec2(size) * 0.5 * params.border_scale;
    float radius = float(min(size.x, size.y)) * 0.5 - 1.0;

    if (params.border_style == 0.0) {
        // No border
        return;
    }

    if (params.border_style == 1.0) {
        // Square border (clamp)
        pos = clamp(pos, -half_bounds, half_bounds - vec2(1.0));
    }
	else if (params.border_style == 2.0) {
		// Circle border (clamp)
		float dist = length(pos);
		float scaled_radius = radius * params.border_scale;
		if (dist > scaled_radius) {
			pos = normalize(pos) * scaled_radius;
		}
	}
    else if (params.border_style == 3.0) {
        // Bouncy square border
        if (pos.x < -half_bounds.x) {
            pos.x = -half_bounds.x;
            vel.x *= -1.0;
        } else if (pos.x > half_bounds.x) {
            pos.x = half_bounds.x;
            vel.x *= -1.0;
        }
        if (pos.y < -half_bounds.y) {
            pos.y = -half_bounds.y;
            vel.y *= -1.0;
        } else if (pos.y > half_bounds.y) {
            pos.y = half_bounds.y;
            vel.y *= -1.0;
        }
    }
	else if (params.border_style == 4.0) {
		// Bouncy circle border
		float dist = length(pos);
		float scaled_radius = radius * params.border_scale;
		if (dist > scaled_radius) {
			vec2 normal = normalize(pos);
			pos = normal * scaled_radius;
			vel = reflect(vel, normal);
		}
	}
}

void run_sim() {
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
	int id = int(uv.y * params.compute_texture_size + uv.x);
	
	if (id >= params.point_count || uv.x >= params.compute_texture_size || uv.y >= params.compute_texture_size) {
		return;
	}	
	vec4 pixel = imageLoad(input_particles, uv);
	
	vec2 pos = pixel.rg;
	vec2 vel = pixel.ba;
    int species = in_species_buffer.data[id];

	// Calculate particle forces
    vec2 force = vec2(0.0);
    for (uint i = 0; i < uint(params.point_count); ++i) {
        if (i == id) continue;

		// Map particle index to 2D texel coordinates
		ivec2 other_uv = ivec2(i % int(params.compute_texture_size), i / params.compute_texture_size);
		vec4 other_pixel = imageLoad(input_particles, other_uv);
		
		// Get particle position
		vec2 other_pos = other_pixel.rg;
		vec2 other_vel = other_pixel.ba;
        int other_species = in_species_buffer.data[i];
		
		// Distance between
		vec2 diff = other_pos - pos;
		float dist = length(diff);
		
		if (dist > 0.0001) {
			vec2 dir = normalize(diff);
			
			// Particle attraction/repulsion (with softening + clamp)
            if (dist < params.interaction_radius) {
                float f = interaction_matrix.data[species * uint(params.species_count) + other_species];
                force += dir * apply_force(f, dist, params.force_softening, params.max_force);
            }

            // Particle collision (with softening + clamp)
            float min_dist = params.collision_radius;
            if (dist < min_dist) {
                float penetration = min_dist - dist;
                float f = penetration * params.collision_strength;
                force -= dir * apply_force(f, dist, params.force_softening, params.max_force); // inverted sign
            }
		} else {
			// in the exact same spot, so push apart in a random direction
			vec2 dir = random_dir(id, i);
			float f = params.collision_strength * params.collision_radius; // tiny force
			force -= dir * apply_force(f, 0.001, params.force_softening, params.max_force);
		}
    }
	
	// Attraction to center
	if (params.center_attraction>0.0001) {
		vec2 center = vec2(0.0);
		vec2 r_center = center - pos;
		float dist_center = length(r_center);
		vec2 dir_center = normalize(r_center);
		force += params.center_attraction * dir_center;
	}

    // Integrate velocity
    vel += force * params.dt;
    //vel += force;
    vel *= params.damping;
	
    // Velocity clamp
	float speed = length(vel);
    if (speed > params.max_velocity) {
        vel = normalize(vel) * params.max_velocity;
    }
	
	// Move
    pos += vel * params.dt;
	
	// Boundary collision
	apply_border(pos, vel);

    // Write back
	imageStore(output_particles, uv, vec4(pos, vel));
}

void main() {
    run_sim();
}
