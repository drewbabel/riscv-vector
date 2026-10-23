// Single step Spike driver

#include <riscv/sim.h>

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

static const reg_t kBase = 0x80000000;
static const reg_t kLines = MIP_MEIP | MIP_MTIP;

struct irq_point_t {
  uint64_t at;
  reg_t mask;
};

class irq_sim_t : public sim_t {
 public:
  using sim_t::sim_t;
  std::vector<irq_point_t> points;
  uint64_t limit = 0;

 private:
  size_t next = 0;
  uint64_t retired = 0;

  void idle() override {
    processor_t* p = get_core(0);
    state_t* s = p->get_state();
    if (retired >= limit) {
      fflush(nullptr);
      std::exit(0);
    }
    // Lines the core saw
    reg_t mask = 0;
    if (next < points.size() && points[next].at == retired) mask = points[next].mask;
    s->mip->backdoor_write_with_mask(kLines, mask);
    reg_t before = s->minstret->read();
    p->step(1);
    bool trapped = s->minstret->read() == before;
    bool irq = (s->mcause->read() >> (p->get_xlen() - 1)) & 1;
    if (mask && !(trapped && irq)) {
      fprintf(stderr, "IRQ MISSED %llu\n", (unsigned long long)retired);
      fflush(nullptr);
      std::exit(0);
    }
    if (mask) next++;
    if (!trapped) retired++;
  }
};

static std::vector<irq_point_t> parse_points(const std::string& text) {
  std::vector<irq_point_t> points;
  if (text == "-") return points;
  size_t pos = 0;
  while (pos < text.size()) {
    size_t end = text.find(',', pos);
    if (end == std::string::npos) end = text.size();
    std::string item = text.substr(pos, end - pos);
    size_t colon = item.find(':');
    points.push_back({std::stoull(item.substr(0, colon)), std::stoull(item.substr(colon + 1))});
    pos = end + 1;
  }
  return points;
}

int main(int argc, char** argv) {
  if (argc != 5) {
    fprintf(stderr, "usage: spike_irq <isa> <limit> <at:mask,...|-> <elf>\n");
    return 2;
  }
  cfg_t cfg;
  cfg.isa = argv[1];
  cfg.hartids = {0};
  cfg.start_pc.set_global(kBase);
  std::vector<std::pair<reg_t, abstract_mem_t*>> mems;
  for (const auto& m : cfg.mem_layout) mems.push_back({m.get_base(), new mem_t(m.get_size())});
  std::vector<device_factory_sargs_t> devices;
  std::vector<std::string> args = {argv[4]};
  debug_module_config_t dm;
  irq_sim_t s(&cfg, false, mems, devices, false, args, dm, nullptr, true, nullptr, false, nullptr,
              std::nullopt);
  s.limit = std::stoull(argv[2]);
  s.points = parse_points(argv[3]);
  s.configure_log(false, true);
  return s.run();
}
