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

all:
	@echo "see README for build instructions"

clean:
	rm -rf simulation build db incremental_db ddr3/ddr3_x32.[a-uw-z0-9A-UW-Z]* ddr3/ddr3_x32 ddr3/ddr3_x32_sim* pcie/pcie_c5_4x.[a-uw-z0-9A-UW-Z]* pcie/pcie_c5_4x pcie/pcie_c5_4x_sim* *.qws */*.qarlog PLLJ_PLLSPE_INFO.txt a5_pin_model_dump.txt ddr3_x32_p0_summary.csv sim/*.ver
	$(MAKE) -C src clean
