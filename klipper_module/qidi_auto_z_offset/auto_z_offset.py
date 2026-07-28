# QIDI Auto Z-Offset support
#
# Copyright (C) 2024  Joe Maples <joe@maples.dev>
# Copyright (C) 2021  Dmitry Butyugin <dmbutyugin@google.com>
# Copyright (C) 2017-2021  Kevin O'Connor <kevin@koconnor.net>
#
# This file may be distributed under the terms of the GNU GPLv3 license.

from operator import neg

from . import probe


class AutoZOffsetCommandHelper(probe.ProbeCommandHelper):
    def __init__(self, config, mcu_probe, query_endstop=None):
        self.printer = config.get_printer()
        self.name = config.get_name()
        gcode = self.printer.lookup_object('gcode')
        self.mcu_probe = mcu_probe
        self.query_endstop = query_endstop
        self.z_offset = config.getfloat("z_offset", -0.1)
        self.probe_hop = config.getfloat("probe_hop", 5.0, minval=4.0)
        self.offset_samples = config.getint("offset_samples", 3, minval=1)
        self.calibrated_z_offset = config.getfloat("calibrated_z_offset", 0.0)
        self.last_state = False
        self.last_z_result = 0.0
        self.last_probe_position = gcode.Coord((0., 0., 0.))

        # Register commands
        self.gcode = self.printer.lookup_object("gcode")
        self.gcode.register_command(
            "AUTO_Z_PROBE",
            self.cmd_AUTO_Z_PROBE,
            desc=self.cmd_AUTO_Z_PROBE_help,
        )
        self.gcode.register_command(
            "AUTO_Z_HOME_Z",
            self.cmd_AUTO_Z_HOME_Z,
            desc=self.cmd_AUTO_Z_HOME_Z_help,
        )
        self.gcode.register_command(
            "AUTO_Z_MEASURE_OFFSET",
            self.cmd_AUTO_Z_MEASURE_OFFSET,
            desc=self.cmd_AUTO_Z_MEASURE_OFFSET_help,
        )
        self.gcode.register_command(
            "AUTO_Z_CALIBRATE",
            self.cmd_AUTO_Z_CALIBRATE,
            desc=self.cmd_AUTO_Z_CALIBRATE_help,
        )
        self.gcode.register_command(
            "AUTO_Z_LOAD_OFFSET",
            self.cmd_AUTO_Z_LOAD_OFFSET,
            desc=self.cmd_AUTO_Z_LOAD_OFFSET_help,
        )
        self.gcode.register_command(
            "AUTO_Z_SAVE_GCODE_OFFSET",
            self.cmd_AUTO_Z_SAVE_GCODE_OFFSET,
            desc=self.cmd_AUTO_Z_SAVE_GCODE_OFFSET_help,
        )

    def _move_to_center(self, gcmd):
        toolhead = self.printer.lookup_object("toolhead")
        params = self.mcu_probe.get_probe_params(gcmd)
        curpos = toolhead.get_position()
        curpos[0] = 120
        curpos[1] = 120
        if curpos[2] < 1.0:
            curpos[2] = self.probe_hop
        self._move(curpos, params["lift_speed"])

    def lift_probe(self, gcmd):
        toolhead = self.printer.lookup_object("toolhead")
        params = self.mcu_probe.get_probe_params(gcmd)
        curpos = toolhead.get_position()
        curpos[2] += self.probe_hop
        self._move(curpos, params["lift_speed"])

    cmd_AUTO_Z_PROBE_help = (
        "Probe Z-height at current XY position using the bed sensors"
    )

    def cmd_AUTO_Z_PROBE(self, gcmd):
        self._move_to_center(gcmd)
        pos = probe.run_single_probe(self.mcu_probe, gcmd)
        self.last_z_result = neg(pos[2]) + self.z_offset
        gcmd.respond_info("Result is z=%.6f" % self.last_z_result)

    cmd_AUTO_Z_HOME_Z_help = "Home Z using the bed sensors as an endstop"

    def cmd_AUTO_Z_HOME_Z(self, gcmd):
        self._move_to_center(gcmd)
        self.lift_probe(gcmd)
        self.cmd_AUTO_Z_PROBE(gcmd)
        toolhead = self.printer.lookup_object("toolhead")
        curpos = toolhead.get_position()
        toolhead.set_position(
            [curpos[0], curpos[1], self.z_offset, curpos[3]], homing_axes=(0, 1, 2)
        )
        self.lift_probe(gcmd)

    cmd_AUTO_Z_MEASURE_OFFSET_help = (
        "Z-Offset measured by the inductive probe after AUTO_Z_HOME_Z"
    )

    def cmd_AUTO_Z_MEASURE_OFFSET(self, gcmd):
        # Use bed sensors to correct z origin
        self.cmd_AUTO_Z_HOME_Z(gcmd)
        gcmd.respond_info(
            "%s: bed sensor measured offset: z=%.6f" % (self.name, self.last_z_result)
        )

        # Account for x/y offset of main probe
        main_probe = self.printer.lookup_object("probe")
        toolhead = self.printer.lookup_object("toolhead")
        params = self.mcu_probe.get_probe_params(gcmd)
        curpos = toolhead.get_position()
        curpos[0] = 120 - main_probe.probe_offsets.x_offset
        curpos[1] = 120 - main_probe.probe_offsets.y_offset
        self._move(curpos, params["lift_speed"])

        # Use main probe to measure its own offset
        pos = probe.run_single_probe(main_probe, gcmd)
        gcmd.respond_info("%s: probe measured offset: z=%.6f" % (self.name, pos[2]))
        self.lift_probe(gcmd)
        return pos[2]

    cmd_AUTO_Z_CALIBRATE_help = (
        "Set the Z-Offset by averaging multiple runs of AUTO_Z_MEASURE_OFFSET"
    )

    def cmd_AUTO_Z_CALIBRATE(self, gcmd):
        # Get average measured offset over self.offset_samples number of tests
        offset_total = 0.0
        for _ in range(self.offset_samples):
            offset_total += self.cmd_AUTO_Z_MEASURE_OFFSET(gcmd)
        self.calibrated_z_offset = neg(offset_total / self.offset_samples)

        # Apply calibrated offset and save to config
        self.gcode.run_script_from_command(
            "SET_GCODE_OFFSET Z=%f MOVE=0" % self.calibrated_z_offset
        )
        configfile = self.printer.lookup_object("configfile")
        configfile.set(
            self.name, "calibrated_z_offset", "%.6f" % self.calibrated_z_offset
        )
        gcmd.respond_info(
            "%s: calibrated_z_offset: %.6f\n"
            "The SAVE_CONFIG command will update the printer config file\n"
            "with the above and restart the printer."
            % (self.name, self.calibrated_z_offset)
        )

    cmd_AUTO_Z_LOAD_OFFSET_help = (
        "Apply the calibrated_z_offset saved in the config file"
    )

    def cmd_AUTO_Z_LOAD_OFFSET(self, gcmd):
        gcmd.respond_info(
            "%s: calibrated_z_offset: %.6f" % (self.name, self.calibrated_z_offset)
        )
        self.gcode.run_script_from_command(
            "SET_GCODE_OFFSET Z=%f MOVE=0" % self.calibrated_z_offset
        )

    cmd_AUTO_Z_SAVE_GCODE_OFFSET_help = (
        "Save the current gcode offset for z as the new calibrated_z_offset"
    )

    def cmd_AUTO_Z_SAVE_GCODE_OFFSET(self, gcmd):
        gcode_move = self.printer.lookup_object("gcode_move")
        self.calibrated_z_offset = gcode_move.homing_position[2]
        configfile = self.printer.lookup_object("configfile")
        configfile.set(
            self.name, "calibrated_z_offset", "%.6f" % self.calibrated_z_offset
        )
        gcmd.respond_info(
            "%s: calibrated_z_offset: %.6f\n"
            "The SAVE_CONFIG command will update the printer config file\n"
            "with the above and restart the printer."
            % (self.name, self.calibrated_z_offset)
        )


# Homing via auto_z_offset:z_virtual_endstop
class HomingViaAutoZHelper(probe.HomingViaProbeHelper):
    def __init__(self, config, mcu_probe, param_helper):
        self.printer = config.get_printer()
        self.mcu_probe = mcu_probe
        self.param_helper = param_helper
        self.multi_probe_pending = False
        self.z_min_position = probe.lookup_minimum_z(config)
        self.results = []
        probe.LookupZSteppers(config, self.mcu_probe.add_stepper)
        # Register z_virtual_endstop pin
        self.printer.lookup_object("pins").register_chip("auto_z_offset", self)
        self.printer.register_event_handler(
            "homing:homing_move_begin", self._handle_homing_move_begin
        )
        self.printer.register_event_handler(
            "homing:homing_move_end", self._handle_homing_move_end
        )
        self.printer.register_event_handler(
            "homing:home_rails_begin", self._handle_home_rails_begin
        )
        self.printer.register_event_handler(
            "homing:home_rails_end", self._handle_home_rails_end
        )
        self.printer.register_event_handler(
            "gcode:command_error", self._handle_command_error
        )


class AutoZOffsetEndstopWrapper:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.gcode = self.printer.lookup_object("gcode")
        self.probe_accel = config.getfloat("probe_accel", 0.0, minval=0.0)
        self.probe_wrapper = probe.ProbeEndstopWrapper(config)
        # Setup prepare_gcode
        gcode_macro = self.printer.load_object(config, "gcode_macro")
        self.prepare_gcode = gcode_macro.load_template(config, "prepare_gcode")
        # Wrappers
        self.get_mcu = self.probe_wrapper.get_mcu
        self.add_stepper = self.probe_wrapper.add_stepper
        self.get_steppers = self.probe_wrapper.get_steppers
        self.home_start = self.probe_wrapper.home_start
        self.home_wait = self.probe_wrapper.home_wait
        self.query_endstop = self.probe_wrapper.query_endstop
        self.multi_probe_end = self.probe_wrapper.multi_probe_end

    def multi_probe_begin(self):
        self.gcode.run_script_from_command(self.prepare_gcode.render())
        self.probe_wrapper.multi_probe_begin()

    def probe_prepare(self, hmove):
        toolhead = self.printer.lookup_object("toolhead")
        self.probe_wrapper.probe_prepare(hmove)
        if self.probe_accel > 0.0:
            systime = self.printer.get_reactor().monotonic()
            toolhead_info = toolhead.get_status(systime)
            self.old_max_accel = toolhead_info["max_accel"]
            self.gcode.run_script_from_command("M204 S%.3f" % self.probe_accel)

    def probe_finish(self, hmove):
        if self.probe_accel > 0.0:
            self.gcode.run_script_from_command("M204 S%.3f" % self.old_max_accel)
        self.probe_wrapper.probe_finish(hmove)


class AutoZOffsetParameterHelper(probe.ProbeParameterHelper):
    def __init__(self, config):
        gcode = config.get_printer().lookup_object("gcode")
        self.dummy_gcode_cmd = gcode.create_gcode_command("", "", {})
        # Configurable probing speeds
        self.speed = config.getfloat("speed", 5.0, above=0.0)
        self.lift_speed = config.getfloat("lift_speed", self.speed, above=0.0)
        # Multi-sample support (for improved accuracy)
        self.sample_count = config.getint("samples", 5, minval=3)
        self.sample_retract_dist = config.getfloat(
            "sample_retract_dist", 2.0, above=0.0
        )
        atypes = {"median": "median", "average": "average"}
        self.samples_result = config.getchoice("samples_result", atypes, "average")
        self.samples_tolerance = config.getfloat("samples_tolerance", 0.100, minval=0.0)
        self.samples_retries = config.getint("samples_tolerance_retries", 0, minval=0)


class AutoZOffsetSessionHelper(probe.ProbeSessionHelper):
    def __init__(self, config, param_helper, start_session_cb):
        self.printer = config.get_printer()
        self.param_helper = param_helper
        self.start_session_cb = start_session_cb
        # Session state
        self.hw_probe_session = None
        self.results = []
        # Register event handlers
        self.printer.register_event_handler(
            "gcode:command_error", self._handle_command_error
        )

    def run_probe(self, gcmd):
        if self.hw_probe_session is None:
            self._probe_state_error()
        params = self.param_helper.get_probe_params(gcmd)
        toolhead = self.printer.lookup_object("toolhead")
        probexy = toolhead.get_position()[:2]
        retries = 0
        positions = []
        sample_count = params["samples"]
        while len(positions) < sample_count:
            # Probe position
            pos = self._probe(gcmd)
            positions.append(pos)
            # Check samples tolerance
            z_positions = [p[2] for p in positions]
            if max(z_positions) - min(z_positions) > params["samples_tolerance"]:
                if retries >= params["samples_tolerance_retries"]:
                    raise gcmd.error("Probe samples exceed samples_tolerance")
                gcmd.respond_info("Probe samples exceed tolerance. Retrying...")
                retries += 1
                positions = []
            # Retract
            if len(positions) < sample_count:
                toolhead.manual_move(
                    probexy + [pos[2] + params["sample_retract_dist"]],
                    params["lift_speed"],
                )
        # Discard highest and lowest values
        positions.remove(max(positions))
        positions.remove(min(positions))
        # Calculate result
        epos = probe.calc_probe_z_average(positions, params["samples_result"])
        self.results.append(epos)


class AutoZOffsetOffsetsHelper:
    def __init__(self, config):
        self.x_offset = 0.0
        self.y_offset = 0.0
        self.z_offset = config.getfloat("z_offset", 0.0)

    def get_offsets(self):
        return 0.0, 0.0, self.z_offset


class AutoZOffsetProbe:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.mcu_probe = AutoZOffsetEndstopWrapper(config)
        self.cmd_helper = AutoZOffsetCommandHelper(
            config, self, self.mcu_probe.query_endstop
        )
        self.probe_offsets = AutoZOffsetOffsetsHelper(config)
        self.param_helper = AutoZOffsetParameterHelper(config)
        self.homing_helper = HomingViaAutoZHelper(
            config, self.mcu_probe, self.param_helper
        )
        self.probe_session = AutoZOffsetSessionHelper(
            config, self.param_helper, self.homing_helper.start_probe_session
        )

    def get_probe_params(self, gcmd=None):
        return self.param_helper.get_probe_params(gcmd)

    def get_offsets(self):
        return self.probe_offsets.get_offsets()

    def get_status(self, eventtime):
        return self.cmd_helper.get_status(eventtime)

    def start_probe_session(self, gcmd):
        return self.probe_session.start_probe_session(gcmd)


def load_config(config):
    auto_z_offset = AutoZOffsetProbe(config)
    config.get_printer().add_object("auto_z_offset", auto_z_offset)
    return auto_z_offset
