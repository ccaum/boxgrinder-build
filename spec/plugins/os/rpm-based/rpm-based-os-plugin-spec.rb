#
# Copyright 2010 Red Hat, Inc.
#
# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as
# published by the Free Software Foundation; either version 3 of
# the License, or (at your option) any later version.
#
# This software is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this software; if not, write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
# 02110-1301 USA, or see the FSF site: http://www.fsf.org.

require 'rubygems'
require 'boxgrinder-build/plugins/os/rpm-based/rpm-based-os-plugin'
require 'hashery/opencascade'

module BoxGrinder
  describe RPMBasedOSPlugin do
    before(:each) do
      @config = mock('Config')
      @appliance_config = mock('ApplianceConfig')
      plugins = mock('Plugins')
      plugins.stub!(:[]).with('rpm_based').and_return({})
      @config.stub!(:[]).with(:plugins).and_return(plugins)
      @config.stub!(:dir).and_return(OpenCascade.new(:tmp => 'tmpdir', :cache => 'cachedir'))
      @config.stub!(:os).and_return(OpenCascade.new(:name => 'fedora', :version => '14'))

      @appliance_config.stub!(:name).and_return('full')
      @appliance_config.stub!(:version).and_return(1)
      @appliance_config.stub!(:release).and_return(0)
      @appliance_config.stub!(:post).and_return({})
      @appliance_config.stub!(:os).and_return(OpenCascade.new({:name => 'fedora', :version => '11'}))
      @appliance_config.stub!(:hardware).and_return(OpenCascade.new(:cpus => 1, :memory => 512, :partitions => {'/' => nil, '/home' => nil}))
      @appliance_config.stub!(:path).and_return(OpenCascade.new(:build => 'build/path', :main => 'mainpath'))

      @plugin = RPMBasedOSPlugin.new

      @plugin.stub!(:merge_plugin_config)

      @plugin.init(@config, @appliance_config, :log => LogHelper.new(:level => :trace, :type => :stdout), :plugin_info => {:name => :rpm_based})

      @config = @plugin.instance_variable_get(:@config)
      @appliance_config = @plugin.instance_variable_get(:@appliance_config)
      @image_helper = @plugin.instance_variable_get(:@image_helper)
      @exec_helper = @plugin.instance_variable_get(:@exec_helper)
      @log = @plugin.instance_variable_get(:@log)
    end

    it "should install repos" do
      @appliance_config.should_receive(:repos).and_return(
          [
              {'name' => 'cirras', 'baseurl' => "http://repo.boxgrinder.org/packages/fedora/11/RPMS/x86_64"},
              {'name' => 'abc', 'baseurl' => 'http://abc', 'mirrorlist' => "http://abc.org/packages/fedora/11/RPMS/x86_64"},
          ])

      guestfs = mock("guestfs")
      guestfs.should_receive(:write_file).with("/etc/yum.repos.d/cirras.repo", "[cirras]\nname=cirras\nenabled=1\ngpgcheck=0\nbaseurl=http://repo.boxgrinder.org/packages/fedora/11/RPMS/x86_64\n", 0)
      guestfs.should_receive(:write_file).with("/etc/yum.repos.d/abc.repo", "[abc]\nname=abc\nenabled=1\ngpgcheck=0\nbaseurl=http://abc\nmirrorlist=http://abc.org/packages/fedora/11/RPMS/x86_64\n", 0)

      @plugin.install_repos(guestfs)
    end

    it "should not install ephemeral repos" do
      @appliance_config.should_receive(:repos).and_return(
          [
              {'name' => 'abc', 'baseurl' => 'http://abc', 'mirrorlist' => "http://abc.org/packages/fedora/11/RPMS/x86_64"},
              {'name' => 'cirras', 'baseurl' => "http://repo.boxgrinder.org/packages/fedora/11/RPMS/x86_64", 'ephemeral' => true}
          ])

      guestfs = mock("guestfs")
      guestfs.should_receive(:write_file).with("/etc/yum.repos.d/abc.repo", "[abc]\nname=abc\nenabled=1\ngpgcheck=0\nbaseurl=http://abc\nmirrorlist=http://abc.org/packages/fedora/11/RPMS/x86_64\n", 0)

      @plugin.install_repos(guestfs)
    end

    it "should read kickstart definition file" do
      @plugin.should_receive(:read_kickstart).with('file.ks')
      @plugin.read_file('file.ks')
    end

    it "should read other definition file" do
      @plugin.should_not_receive(:read_kickstart)
      @plugin.read_file('file.other')
    end

    describe ".read_kickstart" do
      it "should read and parse valid kickstart file with bg comments" do
        appliance_config = @plugin.read_kickstart("#{File.dirname(__FILE__)}/src/jeos-f13.ks")
        appliance_config.should be_an_instance_of(ApplianceConfig)
        appliance_config.os.name.should == 'fedora'
        appliance_config.os.version.should == '13'
      end

      it "should raise while parsing kickstart file *without* bg comments" do
        lambda {
          @plugin.read_kickstart("#{File.dirname(__FILE__)}/src/jeos-f13-plain.ks")
        }.should raise_error("No operating system name specified, please add comment to you kickstrt file like this: # bg_os_name: fedora")
      end

      it "should raise while parsing kickstart file *without* bg version comment" do
        lambda {
          @plugin.read_kickstart("#{File.dirname(__FILE__)}/src/jeos-f13-without-version.ks")
        }.should raise_error("No operating system version specified, please add comment to you kickstrt file like this: # bg_os_version: 14")
      end

      it "should read kickstart and populate partitions" do
        appliance_config = @plugin.read_kickstart("#{File.dirname(__FILE__)}/src/jeos-f13.ks")
        appliance_config.should be_an_instance_of(ApplianceConfig)
        appliance_config.hardware.partitions.should == {'/' => {'size' => 2.0, 'type' => 'ext4'}, '/home' => {'size' => 3.0, 'type' => 'ext3', "options" => "abc,def,gef"}}
      end

      it "should read kickstart and populate partitions" do
        appliance_config = @plugin.read_kickstart("#{File.dirname(__FILE__)}/src/jeos-f13.ks")
        appliance_config.should be_an_instance_of(ApplianceConfig)
        appliance_config.hardware.partitions.should == {'/' => {'size' => 2.0, 'type' => 'ext4'}, '/home' => {'size' => 3.0, 'type' => 'ext3', "options" => "abc,def,gef"}}
      end

      it "should read kickstart and raise because of no partition size specified" do
        File.should_receive(:read).with("jeos-f13.ks").and_return("# bg_os_name: fedora\n# bg_os_version: 14\npart /")

        lambda {
          @plugin.read_kickstart("jeos-f13.ks")
        }.should raise_error("Partition size not specified for / partition in jeos-f13.ks")
      end

      it "should read kickstart and raise because no os name is specified" do
        File.should_receive(:read).with("jeos-f13.ks").and_return("")

        lambda {
          @plugin.read_kickstart("jeos-f13.ks")
        }.should raise_error("No operating system name specified, please add comment to you kickstrt file like this: # bg_os_name: fedora")
      end

      it "should read kickstart and raise because no os version is specified" do
        File.should_receive(:read).with("jeos-f13.ks").and_return("# bg_os_name: rhel")

        lambda {
          @plugin.read_kickstart("jeos-f13.ks")
        }.should raise_error("No operating system version specified, please add comment to you kickstrt file like this: # bg_os_version: 14")
      end

      it "should read kickstart and raise because no partitions are specified" do
        File.should_receive(:read).with("jeos-f13.ks").and_return("# bg_os_name: fedora\n# bg_os_version: 14")

        lambda {
          @plugin.read_kickstart("jeos-f13.ks")
        }.should raise_error("No partitions specified in your kickstart file jeos-f13.ks")
      end
    end

    describe ".use_labels_for_partitions" do
      it "should use labels for partitions instead of paths" do
        guestfs = mock("guestfs")

        guestfs.should_receive(:list_devices).and_return(['/dev/hda'])

        guestfs.should_receive(:read_file).with('/etc/fstab').and_return("/dev/sda1 / something\nLABEL=/boot /boot something\n")
        guestfs.should_receive(:vfs_label).with('/dev/hda1').and_return('/')
        guestfs.should_receive(:write_file).with('/etc/fstab', "LABEL=/ / something\nLABEL=/boot /boot something\n", 0)

        guestfs.should_receive(:read_file).with('/boot/grub/grub.conf').and_return("default=0\ntimeout=5\nsplashimage=(hd0,0)/boot/grub/splash.xpm.gz\nhiddenmenu\ntitle f14-core (2.6.35.10-74.fc14.x86_64)\nroot (hd0,0)\nkernel /boot/vmlinuz-2.6.35.10-74.fc14.x86_64 ro root=/dev/sda1\ninitrd /boot/initramfs-2.6.35.10-74.fc14.x86_64.img")
        guestfs.should_receive(:vfs_label).with('/dev/hda1').and_return('/')
        guestfs.should_receive(:write_file).with('/boot/grub/grub.conf', "default=0\ntimeout=5\nsplashimage=(hd0,0)/boot/grub/splash.xpm.gz\nhiddenmenu\ntitle f14-core (2.6.35.10-74.fc14.x86_64)\nroot (hd0,0)\nkernel /boot/vmlinuz-2.6.35.10-74.fc14.x86_64 ro root=LABEL=/\ninitrd /boot/initramfs-2.6.35.10-74.fc14.x86_64.img", 0)

        @plugin.use_labels_for_partitions(guestfs)
      end

      it "should not change anything" do
        guestfs = mock("guestfs")

        guestfs.should_receive(:list_devices).and_return(['/dev/sda'])

        guestfs.should_receive(:read_file).with('/etc/fstab').and_return("LABEL=/ / something\nLABEL=/boot /boot something\n")
        guestfs.should_not_receive(:vfs_label)
        guestfs.should_not_receive(:write_file)

        guestfs.should_receive(:read_file).with('/boot/grub/grub.conf').and_return("default=0\ntimeout=5\nsplashimage=(hd0,0)/boot/grub/splash.xpm.gz\nhiddenmenu\ntitle f14-core (2.6.35.10-74.fc14.x86_64)\nroot (hd0,0)\nkernel /boot/vmlinuz-2.6.35.10-74.fc14.x86_64 ro root=LABEL=/\ninitrd /boot/initramfs-2.6.35.10-74.fc14.x86_64.img")
        guestfs.should_not_receive(:vfs_label)
        guestfs.should_not_receive(:write_file)

        @plugin.use_labels_for_partitions(guestfs)
      end
    end

    it "should disable the firewall" do
      guestfs = mock("guestfs")
      guestfs.should_receive(:sh).with('lokkit -q --disabled')

      @plugin.disable_firewall(guestfs)
    end

    describe ".build_with_appliance_creator" do
      def do_build
        kickstart = mock(Kickstart)
        kickstart.should_receive(:create).and_return('kickstart.ks')

        validator = mock(RPMDependencyValidator)
        validator.should_receive(:resolve_packages)

        Kickstart.should_receive(:new).with(@config, @appliance_config, {}, {:tmp=>"build/path/rpm_based-plugin/tmp", :base=>"build/path/rpm_based-plugin"}, :log => @log).and_return(kickstart)
        RPMDependencyValidator.should_receive(:new).and_return(validator)

        @exec_helper.should_receive(:execute).with("appliance-creator -d -v -t 'build/path/rpm_based-plugin/tmp' --cache=cachedir/rpms-cache/mainpath --config 'kickstart.ks' -o 'build/path/rpm_based-plugin/tmp' --name 'full' --vmem 512 --vcpu 1 --format raw")

        FileUtils.should_receive(:mv)
        FileUtils.should_receive(:rm_rf)

        guestfs = mock("GuestFS")
        guestfs_helper = mock("GuestFSHelper")

        @image_helper.should_receive(:customize).with(["build/path/rpm_based-plugin/tmp/full-sda.raw"]).and_yield(guestfs, guestfs_helper)

        guestfs.should_receive(:upload).with("/etc/resolv.conf", "/etc/resolv.conf")

        @plugin.should_receive(:change_configuration).with(guestfs_helper)
        @plugin.should_receive(:apply_root_password).with(guestfs)
        @plugin.should_receive(:use_labels_for_partitions).with(guestfs)
        @plugin.should_receive(:disable_firewall).with(guestfs)
        @plugin.should_receive(:set_motd).with(guestfs)
        @plugin.should_receive(:install_repos).with(guestfs)

        guestfs.should_receive(:exists).with('/etc/init.d/firstboot').and_return(1)
        guestfs.should_receive(:sh).with('chkconfig firstboot off')

        yield guestfs, guestfs_helper if block_given?
      end

      it "should build appliance" do
        @appliance_config.stub!(:os).and_return(OpenCascade.new({:name => 'fedora', :version => '14'}))
        do_build
        @plugin.build_with_appliance_creator('jeos.appl')
      end

      it "should execute additional steps for Fedora 15" do
        @appliance_config.stub!(:os).and_return(OpenCascade.new({:name => 'fedora', :version => '15'}))

        do_build do |guestfs, guestfs_helper|
          @plugin.should_receive(:disable_biosdevname).with(guestfs)
          @plugin.should_receive(:change_runlevel).with(guestfs)
          @plugin.should_receive(:disable_netfs).with(guestfs)
          @plugin.should_receive(:recreate_rpm_database).with(guestfs, guestfs_helper)
        end

        @plugin.build_with_appliance_creator('jeos.appl')
      end
    end

    describe ".execute_appliance_creator" do
      it "should execute appliance creator successfuly" do
        @exec_helper.should_receive(:execute).with("appliance-creator -d -v -t 'build/path/rpm_based-plugin/tmp' --cache=cachedir/rpms-cache/mainpath --config 'kickstart.ks' -o 'build/path/rpm_based-plugin/tmp' --name 'full' --vmem 512 --vcpu 1 --format raw")
        @plugin.execute_appliance_creator('kickstart.ks')
      end

      it "should catch the interrupt and unmount the appliance-creator mounts" do
        @exec_helper.should_receive(:execute).with("appliance-creator -d -v -t 'build/path/rpm_based-plugin/tmp' --cache=cachedir/rpms-cache/mainpath --config 'kickstart.ks' -o 'build/path/rpm_based-plugin/tmp' --name 'full' --vmem 512 --vcpu 1 --format raw").and_raise(InterruptionError.new(12345))
        @plugin.should_receive(:cleanup_after_appliance_creator).with(12345)
        @plugin.should_receive(:abort)
        @plugin.execute_appliance_creator('kickstart.ks')
      end
    end

    describe ".cleanup_after_appliance_creator" do
      it "should cleanup after appliance creator (surprisngly!)" do
        Process.should_receive(:kill).with("TERM", 12345)
        Process.should_receive(:wait).with(12345)

        Dir.should_receive(:[]).with('build/path/rpm_based-plugin/tmp/imgcreate-*').and_return(['adir'])

        @exec_helper.should_receive(:execute).ordered.with("mount | grep adir | awk '{print $1}'").and_return("/dev/mapper/loop0p1
/dev/mapper/loop0p2
/sys
/proc
/dev/pts
/dev/shm
/var/cache/boxgrinder/rpms-cache/x86_64/fedora/14")

        @exec_helper.should_receive(:execute).ordered.with('umount -d adir/install_root/var/cache/yum')
        @exec_helper.should_receive(:execute).ordered.with('umount -d adir/install_root/dev/shm')
        @exec_helper.should_receive(:execute).ordered.with('umount -d adir/install_root/dev/pts')
        @exec_helper.should_receive(:execute).ordered.with('umount -d adir/install_root/proc')
        @exec_helper.should_receive(:execute).ordered.with('umount -d adir/install_root/sys')
        @exec_helper.should_receive(:execute).ordered.with('umount -d adir/install_root/home')
        @exec_helper.should_receive(:execute).ordered.with('umount -d adir/install_root/')

        @exec_helper.should_receive(:execute).ordered.with("/sbin/kpartx -d /dev/loop0")
        @exec_helper.should_receive(:execute).ordered.with("losetup -d /dev/loop0")

        @exec_helper.should_receive(:execute).ordered.with("rm /dev/loop01")
        @exec_helper.should_receive(:execute).ordered.with("rm /dev/loop02")

        @plugin.cleanup_after_appliance_creator(12345)
      end
    end

    describe ".recreate_rpm_database" do
      it "should recreate RPM database" do
        guestfs = mock("GuestFS")
        guestfs_helper = mock("GuestFSHelper")

        guestfs.should_receive(:download).with("/var/lib/rpm/Packages", "build/path/rpm_based-plugin/tmp/Packages")
        @exec_helper.should_receive(:execute).with("/usr/lib/rpm/rpmdb_dump build/path/rpm_based-plugin/tmp/Packages > build/path/rpm_based-plugin/tmp/Packages.dump")
        guestfs.should_receive(:upload).with("build/path/rpm_based-plugin/tmp/Packages.dump", "/tmp/Packages.dump")
        guestfs.should_receive(:sh).with("rm -rf /var/lib/rpm/*")
        guestfs_helper.should_receive(:sh).with("cd /var/lib/rpm/ && cat /tmp/Packages.dump | /usr/lib/rpm/rpmdb_load Packages")
        guestfs_helper.should_receive(:sh).with("rpm --rebuilddb")

        @plugin.recreate_rpm_database(guestfs, guestfs_helper)
      end
    end

    context "BGBUILD-204" do
      it "should disable bios device name hints" do
        guestfs = mock("GuestFS")
        guestfs.should_receive(:sh).with("sed -i \"s/kernel\\(.*\\)/kernel\\1 biosdevname=0/g\" /boot/grub/grub.conf")
        @plugin.disable_biosdevname(guestfs)
      end

      it "should change to runlevel 3 by default" do
        guestfs = mock("GuestFS")
        guestfs.should_receive(:rm).with("/etc/systemd/system/default.target")
        guestfs.should_receive(:ln_sf).with("/lib/systemd/system/multi-user.target", "/etc/systemd/system/default.target")
        @plugin.change_runlevel(guestfs)
      end

      it "should disable netfs" do
        guestfs = mock("GuestFS")
        guestfs.should_receive(:sh).with("chkconfig netfs off")
        @plugin.disable_netfs(guestfs)
      end
    end
  end
end
