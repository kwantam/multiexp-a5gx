# vim: syntax=sdc
#
# This file is part of multiexp-a5gx.
#
# multiexp-a5gx is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see http://www.gnu.org/licenses/.

# Clock constraints
create_clock -name "pcie_refclk" -period 10.000ns [get_ports {pcie_refclk}]
create_clock -name "clkin_100_p" -period 10.000ns [get_ports {clkin_100_p}]

# Automatically constrain PLL and other generated clocks
derive_pll_clocks -create_base_clocks

# Automatically calculate clock uncertainty to jitter and other effects.
derive_clock_uncertainty

#set_false_path -from *|*c0|hmc_inst~FF_* -to *p0|*umemphy|*lfifo~LFIFO_IN_READ_EN_DFF
#set_false_path -from *|*p0|*umemphy|hphy_inst~FF_* -to *p0|*umemphy|*vfifo~INC_WR_PTR_DFF
#set_false_path -from *|*c0|hmc_inst~FF_* -to *p0|*umemphy|*vfifo~QVLD_IN_DFF
#set_false_path -from *|*p0|*umemphy|hphy_inst~FF_* -to *p0|*umemphy|*altdq_dqs2_inst|phase_align_os~DFF*

set_false_path -to [get_ports "user_led*"]
set_false_path -to [get_ports "extra_led*"]
set_false_path -to [get_ports "hsma_*"]
set_false_path -from [get_ports "user_pb*"]

# false path to reset registers in mpfe_rst
set_false_path -to [get_keepers "imexp|idram|rstins|*_reg[*]"]
set_false_path -to [get_keepers "imexp|idram|rstins|*_sync[*]"]

# false path from reset timer to reset registers in dram controller
set_false_path -from [get_keepers "imexp|idram|rstins|reset_timer[*]"] -to [get_clocks "imexp|idram|ddrins|*"]

# false path from async reset for fifos that cross clock domains
set_false_path -from [get_keepers "ixilly|*|quiesce"] -to [get_keepers "f_fromhost|*"]
set_false_path -from [get_keepers "imexp|idram|rstins|ctrl_reg[1]"] -to [get_keepers "f_tohost|*"]

# incoming reset false paths to PLL resets
set_false_path -from [get_ports pcie_perstn] -to [get_keepers "ixilly|*"]
set_false_path -from [get_ports pcie_perstn] -to [get_keepers "ipll|*"]
