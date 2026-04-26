#[compute]
#version 450
layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
shared uint prefix_sum_temp[256]; // adjust size to local_size_x*local_size_y
shared uint block_base;

struct MyVec2 {
  vec2 v;
};

// Image buffers with encoded particle data
// R=pos.x, G=pos.y, B=vel.x, A=vel.y
layout(rgba32f, set = 0, binding = 0) uniform restrict image2D input_particles;
layout(rgba32f, set = 1, binding = 0) uniform restrict image2D output_particles;

// Species buffer which is passed as input
layout(set = 0, binding = 1, std430) buffer InSpeciesBuffer { int data[]; }
in_species_buffer;

// Interaction matrix (species_count x species_count)
layout(set = 0, binding = 2, std430) readonly buffer MatrixBuffer {
  float data[];
}
interaction_matrix;

// === Spatial Hashing Buffers ===
// Particles are also called agents here.

// Agent count per cell. [cell] -> count. Array length is number of cells.
layout(set = 0, binding = 3, std430) buffer CellCountBuffer {
  uint cell_counts[];
}
cell_count_buffer;

// Per-cell offsets. Used as a cell starting offset in sorted index buffer.
// Array length is number of cells.
layout(set = 0, binding = 4, std430) buffer CellOffsetBuffer {
  uint cell_offsets[];
}
cell_offset_buffer;

// List of agent IDs grouped by cell. Used for quick iteration through cell
// members. Array length is point count.
layout(set = 0, binding = 5, std430) buffer SortedIndexBuffer {
  uint sorted_indices[];
}
sorted_index_buffer;

// Agent to cell mapping. Array length is point count.
layout(set = 0, binding = 6, std430) buffer AgentCellBuffer { uint data[]; }
agent_cell_buffer;

// Current cursor for each cell in sorted index buffer array. Initial value is
// provided from prefix sum. Mainly used during index sorting. 0-index is used
// during prefix sum for a different purpose - calculating total. Array length
// is number of cells.
layout(set = 0, binding = 7, std430) buffer CursorBuffer { uint data[]; }
cursor_buffer;

// Parameters
layout(push_constant, std430) uniform Params {
  float run_mode;
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
  float world_size_mult;
  float center_attraction;
  float force_softening;
  float max_force;
  float max_velocity;
  // Uniform grid
  float cell_size;     // hashing cell size
  float cells_per_row; // hashing cells per row
}
params;

const float epsilon = 0.0001;

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

  // No border
  if (params.border_style == 0) {
    return;
  }
  // Square border (clamp)
  if (params.border_style == 1) {
    pos = clamp(pos, -half_bounds, half_bounds - vec2(1.0));
  }
  // Circle border (clamp)
  if (params.border_style == 2) {
    float dist = length(pos);
    float scaled_radius = radius * params.border_scale;
    if (dist > scaled_radius) {
      pos = normalize(pos) * scaled_radius;
    }
  }
  // Bouncy square border
  if (params.border_style == 3) {
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
  // Bouncy circle border
  if (params.border_style == 4) {
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

  if (id >= params.point_count || uv.x >= params.compute_texture_size ||
      uv.y >= params.compute_texture_size) {
    return;
  }

  vec4 pixel = imageLoad(input_particles, uv);
  vec2 pos = pixel.rg;
  vec2 vel = pixel.ba;
  int species = in_species_buffer.data[id];

  // Map particle position to a cell
  float cs = params.cell_size;
  int cpr = int(params.cells_per_row);
  float world_size = params.image_size * params.world_size_mult;
  float half_world_size = world_size / 2.0;

  vec2 pos_wrapped = mod(pos + half_world_size + world_size, world_size);
  ivec2 c = ivec2(floor(pos_wrapped / cs)) % cpr;

  // Calculate particle forces
  vec2 force = vec2(0.0);
  // Iterate through current and neighbouring cells
  for (int dx = -1; dx <= 1; ++dx) {
    for (int dy = -1; dy <= 1; ++dy) {
      ivec2 d = ivec2(dx, dy);
      ivec2 nc = ivec2(c + d + cpr) % cpr;
      uint cell = uint(nc.y * cpr + nc.x);

      uint start = cell_offset_buffer.cell_offsets[cell];
      uint end = start + cell_count_buffer.cell_counts[cell];

      for (uint k = start; k < end; ++k) {
        uint other = sorted_index_buffer.sorted_indices[k];
        if (other == id) {
          continue;
        }

        // Map particle index to 2D texel coordinates
        ivec2 other_uv = ivec2(other % int(params.compute_texture_size),
                               other / params.compute_texture_size);
        vec4 other_pixel = imageLoad(input_particles, other_uv);

        // Get particle position
        vec2 other_pos = other_pixel.rg;
        vec2 other_vel = other_pixel.ba;
        int other_species = in_species_buffer.data[other];

        // Distance between
        vec2 diff = other_pos - pos;
        float dist = length(diff);

        if (dist > epsilon) {
          vec2 dir = normalize(diff);

          // Particle attraction/repulsion (with softening + clamp)
          if (dist < params.interaction_radius) {
            float f =
                interaction_matrix
                    .data[species * uint(params.species_count) + other_species];
            force += dir * apply_force(f, dist, params.force_softening,
                                       params.max_force);
          }

          // Particle collision (with softening + clamp)
          float min_dist = params.collision_radius;
          if (dist < min_dist) {
            float penetration = min_dist - dist;
            float f = penetration * params.collision_strength;
            force -= dir * apply_force(f, dist, params.force_softening,
                                       params.max_force); // inverted sign
          }
        } else {
          // In the exact same spot, so push apart in a random direction
          vec2 dir = random_dir(id, other);
          // Tiny force
          float f = params.collision_strength * params.collision_radius;
          force -= dir * apply_force(f, 0.001, params.force_softening,
                                     params.max_force);
        }
      }
    }
  }

  // Attraction to center
  if (params.center_attraction > epsilon) {
    vec2 center = vec2(0.0);
    vec2 r_center = center - pos;
    float dist_center = length(r_center);
    vec2 dir_center = normalize(r_center);
    force += params.center_attraction * dir_center;
  }

  // Integrate velocity
  vel += force * params.dt;

  // Damping
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

  // Write output
  imageStore(output_particles, uv, vec4(pos, vel));
}

// Includes setting agent -> cell mapping
void count_cells() {
  ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
  uint id = uint(uv.y * params.compute_texture_size + uv.x);

  if (id >= params.point_count || uv.x >= params.compute_texture_size ||
      uv.y >= params.compute_texture_size) {
    return;
  }

  vec4 pixel = imageLoad(input_particles, uv);
  vec2 pos = pixel.rg;

  // Map particle position to a cell
  float cs = params.cell_size;
  int cpr = int(params.cells_per_row);
  float world_size = params.image_size * params.world_size_mult;
  float half_world_size = world_size / 2.0;

  vec2 pos_wrapped = mod(pos + half_world_size + world_size, world_size);
  ivec2 c = ivec2(floor(pos_wrapped / cs)) % cpr;
  uint cell = uint(c.y * cpr + c.x);

  // Assign agent -> cell mapping
  agent_cell_buffer.data[id] = cell;

  // Increment per-cell count
  atomicAdd(cell_count_buffer.cell_counts[cell], 1u);
}

void prefix_sum() {
  const uint L =
      gl_WorkGroupSize.x *
      gl_WorkGroupSize.y; // 256u; // adjust size to local_size_x*local_size_y
  uint tid =
      gl_LocalInvocationID.y * gl_WorkGroupSize.x + gl_LocalInvocationID.x;
  uint group_id = gl_WorkGroupID.x;
  uint num_cells = uint(params.cells_per_row) * uint(params.cells_per_row);

  if (group_id == 0u && tid == 0u) {
    cursor_buffer.data[0] = 0u;
  }
  barrier();

  uint val = 0u;
  uint index = group_id * L + tid;
  if (index < num_cells) {
    val = cell_count_buffer.cell_counts[index];
  }
  prefix_sum_temp[tid] = val;
  barrier();

  for (uint offset = 1u; offset < L; offset <<= 1u) {
    uint step = offset << 1u;
    uint ix = (tid + 1u) * step - 1u;
    if (ix < L) {
      prefix_sum_temp[ix] += prefix_sum_temp[ix - offset];
    }
    barrier();
  }

  uint block_total = prefix_sum_temp[L - 1u];
  if (tid == 0u) {
    prefix_sum_temp[L - 1u] = 0u;
  }
  barrier();

  for (uint offset = L >> 1u; offset >= 1u; offset >>= 1u) {
    uint step = offset << 1u;
    uint ix = (tid + 1u) * step - 1u;
    if (ix < L) {
      uint t = prefix_sum_temp[ix - offset];
      prefix_sum_temp[ix - offset] = prefix_sum_temp[ix];
      prefix_sum_temp[ix] += t;
    }
    barrier();
    if (offset == 1u) {
      break;
    }
  }

  if (tid == 0u) {
    block_base = atomicAdd(cursor_buffer.data[0], block_total);
  }
  barrier();
  uint base = block_base;

  if (index < num_cells) {
    uint offset_for_cell = base + prefix_sum_temp[tid];
    cell_offset_buffer.cell_offsets[index] = offset_for_cell;
    cursor_buffer.data[index] = offset_for_cell;
  }
}

void scatter_sorted_indices() {
  uint width = gl_NumWorkGroups.x * gl_WorkGroupSize.x;
  uint id = gl_GlobalInvocationID.y * width + gl_GlobalInvocationID.x;
  if (id >= uint(params.point_count)) {
    return;
  }

  uint cell = agent_cell_buffer.data[id];
  uint pos = atomicAdd(cursor_buffer.data[cell], 1u);
  sorted_index_buffer.sorted_indices[pos] = id;
}

void main() {
  if (params.dt < epsilon) {
    return;
  }

  // ---- GPU preprocessing modes ----
  // COUNT CELLS
  if (params.run_mode == 10) {
    count_cells();
  }
  // PREFIX SUM
  if (params.run_mode == 11) {
    prefix_sum();
  }
  // SCATTER
  if (params.run_mode == 12) {
    scatter_sorted_indices();
  }

  // ---- GPU processing modes ----
  if (params.run_mode == 0) {
    run_sim();
  }
}
