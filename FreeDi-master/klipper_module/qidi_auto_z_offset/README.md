# Auto Z-Offset Calibration for the QIDI Q1 Pro

This is a plugin for Klipper that makes use of the QIDI Q1 Pro's bed sensors to automatically set the toolheads Z-Offset.

> [!IMPORTANT]
> This adapts changes from the QIDI Q1 stock klipper to work with mainline klipper. This is not for use with the stock Q1 firmware.

### Install

```
cd ~
git clone https://github.com/frap129/qidi_auto_z_offset
ln -s ~/qidi_auto_z_offset/auto_z_offset.py ~/klipper/klippy/extras/auto_z_offset.py
```

### Command Reference

**AUTO_Z_PROBE**: Probe Z-height at current XY position using the bed sensors

**AUTO_Z_HOME_Z**: Home Z using the bed sensors as an endstop

**AUTO_Z_MEASURE_OFFSET** Z-Offset measured by the inductive probe after AUTO_Z_HOME_Z

**AUTO_Z_CALIBRATE**: Set the Z-Offset by averaging multiple runs of AUTO_Z_MEASURE_OFFSET

**AUTO_Z_LOAD_OFFSET**: Apply the calibrated_z_offset saved in the config file

**AUTO_Z_SAVE_GCODE_OFFSET**: Save the current gcode offset for z as the new calibrated_z_offset

### Basic Usage

`auto_z_offset` helps calibrate the z_offset of the inductive probe on the Q1 using the piezo electric sensors under the bed.
It allows for finetuning, saving, and loading the calibrated offset.

⚠️ **NOTE** ⚠️
`AUTO_Z_CALIBRATE` should not be used in a `PRINT_START` macro! On rare occasion, the bed sensors can fail to trigger or
trigger too late. If this happens when a print is started, you can end up grinding the nozzle into the bed. Instead, you
should calibrate it prior to your first print, and load the offset in `PRINT_START`.

First, calibrate the z_offset:

1. Heat the extruder to a reasonable temperature that wont ooze (160+)
2. Home all axes
3. Run `AUTO_Z_CALIBRATE`
4. Move Z to 0
5. Verify that you can slide a piece of paper under the nozzle
6. Run `SAVE_CONFIG` to save the measured offset.
   - Note, this does not modify the `z_offset` of the inductive probe in your config. This value is only used by
     `auto_z_offset`

Add `AUTO_Z_LOAD_OFFSET` to your `PRINT_START` macro to load the value every time you start a print. If you make adujstments to
the offset by micro-stepping durring a print, you can save that with `AUTO_Z_SAVE_GCODE_OFFSET` and `SAVE_CONFIG`

### Config Reference

```
[auto_z_offset]
pin:
#   Pin connected to the Auto Z Offset output pin. This parameter is required.
z_offset:
#   The offset between measured 0 and when the bed sensors trigger.
#   default is -0.1
prepare_gcode:
#   gcode script to run before probing with auto_z_offset. This is required, and an
#   example script is provided below.
#probe_accel:
#   If set, limits the acceleration of the probing moves (in mm/sec^2).
#   A sudden large acceleration at the beginning of the probing move may
#   cause spurious probe triggering, especially if the hotend is heavy.
#   To prevent that, it may be necessary to reduce the acceleration of
#   the probing moves via this parameter.
#probe_hop:
#   The amount to hop between probing with bed sensors and probing with probe.
#   default is 5.0, min is 4.0 to avoid triggering the probe early
#offset_samples:
#   The number of times to probe with bed sensors and inductive probe when running
#   AUTO_Z_CALIBRATE. Note this is not the same as `samples`.
#   default is 3
#speed:
#samples:
#sample_retract_dist:
#samples_result:
#samples_tolerance:
#samples_tolerance_retries:
#activate_gcode:
#deactivate_gcode:
#deactivate_on_each_sample:
#   See the "probe" section for more information on the parameters above.
```

### Example Configuration from OpenQ1

This example config also includes the control pin for the bed sensors and the config for the inductive probe. Use them as shown for the best compatiblity.

```
[output_pin bed_sensor]
pin: !U_1:PA14
value:0

[probe]
pin: !gpio21
x_offset: 17.6
y_offset: 4.4
z_offset: 0.0
speed:10
samples: 3
samples_result: average
sample_retract_dist: 4.0
samples_tolerance: 0.05
samples_tolerance_retries: 5

[auto_z_offset]
pin: U_1:PC1
z_offset: -0.1
speed: 10
probe_accel: 50
samples: 5
samples_result: average
samples_tolerance: 0.05
samples_tolerance_retries: 5
prepare_gcode:
    SET_PIN PIN=bed_sensor VALUE=0
    G91
    {% set i = 4 %}
    {% for iteration in range(i|int) %}
        G1 Z1 F900
        G1 Z-1 F900
    {% endfor %}
    G90
    SET_PIN PIN=bed_sensor VALUE=1
```
