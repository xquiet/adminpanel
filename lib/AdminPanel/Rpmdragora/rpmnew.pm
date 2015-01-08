# vim: set et ts=4 sw=4:
package AdminPanel::Rpmdragora::rpmnew;
#*****************************************************************************
#
#  Copyright (c) 2002 Guillaume Cottenceau
#  Copyright (c) 2002-2007 Thierry Vignaud <tvignaud@mandriva.com>
#  Copyright (c) 2003, 2004, 2005 MandrakeSoft SA
#  Copyright (c) 2005-2007 Mandriva SA
#  Copyright (c) 2013 - 2015 Matteo Pasotti <matteo.pasotti@gmail.com>
#  Copyright (c) 2014 - 2015 Angelo Naselli <anaselli@linux.it>
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2, as
#  published by the Free Software Foundation.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#
#*****************************************************************************
#
# $Id: rpmnew.pm 263914 2009-12-03 17:41:02Z tv $

use strict;
use Text::Diff;
use MDK::Common::Math qw(sum);
use MDK::Common::File qw(renamef);
use MDK::Common::Various qw(chomp_);

use AdminPanel::rpmdragora;
use AdminPanel::Rpmdragora::init;
use AdminPanel::Rpmdragora::pkg;
use AdminPanel::Rpmdragora::open_db;
use AdminPanel::Rpmdragora::formatting;

use yui;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(rpmnew_dialog do_merge_if_needed);

my $loc = AdminPanel::rpmdragora::locale();

# /var/lib/nfs/etab /var/lib/nfs/rmtab /var/lib/nfs/xtab /var/cache/man/whatis
my %ignores_rpmnew = map { $_ => 1 } qw(
    /etc/adjtime
    /etc/fstab
    /etc/group
    /etc/ld.so.conf
    /etc/localtime
    /etc/modules
    /etc/passwd
    /etc/security/fileshare.conf
    /etc/shells
    /etc/sudoers
    /etc/sysconfig/alsa
    /etc/sysconfig/autofsck
    /etc/sysconfig/harddisks
    /etc/sysconfig/harddrake2/previous_hw
    /etc/sysconfig/init
    /etc/sysconfig/installkernel
    /etc/sysconfig/msec
    /etc/sysconfig/nfs
    /etc/sysconfig/pcmcia
    /etc/sysconfig/rawdevices
    /etc/sysconfig/saslauthd
    /etc/sysconfig/syslog
    /etc/sysconfig/usb
    /etc/sysconfig/xinetd
);


#=============================================================

=head2 _rpmnewFile

=head3 INPUT

    $filename: configuration file name

=head3 OUTPUT

    $rpmnew_filename: new configuration file name

=head3 DESCRIPTION

    This function evaluate the new configration file generated by
    the update

=cut

#=============================================================
sub _rpmnewFile ($) {
    my $filename = shift;

    my ($rpmnew, $rpmsave) = ("$filename.rpmnew", "$filename.rpmsave");
    my $rpmfile = 'rpmnew';
    -r $rpmnew or $rpmfile = 'rpmsave';
    -r $rpmnew && -r $rpmsave && (stat $rpmsave)[9] > (stat $rpmnew)[9] and $rpmfile = 'rpmsave';
    $rpmfile eq 'rpmsave' and $rpmnew = $rpmsave;

    return $rpmnew;
}

#=============================================================

=head2 _performDiff

=head3 INPUT

    $file: configuration file name
    $diffBox: YWidget that will show the difference

=head3 DESCRIPTION

    This function gets the configuration file perfomrs
    the difference with the new one and shows it into the
    $diffBox

=cut

#=============================================================
sub _performDiff ($$) {
    my ($file, $diffBox) = @_;

    my $rpmnew = _rpmnewFile($file);

    foreach (qw(LANG LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION LC_ALL)) {
        local $ENV{$_} = $ENV{$_} . '.UTF-8' if $ENV{$_} && $ENV{$_} !~ /UTF-8/;
    }

    my $diff = diff $file, $rpmnew, { STYLE => "Unified" };
    $diff = $loc->N("(none)") if !$diff;

    my @lines = split ("\n", $diff);
    ## adding color lines to diff
    foreach my $line (@lines) {
        if (substr ($line, 0, 1) eq "+") {
            $line =~ s|^\+(.*)|<font color="green">+$1</font>|;
        }
        elsif (substr ($line, 0, 1) eq "-") {
            $line =~ s|^\-(.*)|<font color="red">-$1</font>|;
        }
        elsif (substr ($line, 0, 1) eq "@") {
            $line =~ s|(.*)|<font color="blue">$1</font>|;
        }
        else {
            $line =~ s|(.*)|<font color="black">$1</font>|;
        }
    }
    $diff = join("<br>", @lines);

    ensure_utf8($diff);
    $diffBox->setValue($diff);

    return;
}

#=============================================================

=head2 rpmnew_dialog

=head3 INPUT

    $msg: message to be shown during the choice
    %o2r: HASH containing {
            the package name => ARRAY of configration files
        }

=head3 OUTPUT

    1 if nothing to do or 0 after user interaction

=head3 DESCRIPTION

    This function shows the configuration files difference and
    asks for action to be performed

=cut

#=============================================================
sub rpmnew_dialog {
    my ($msg, %p2r) = @_;

    @{$p2r{$_}} = grep { !$ignores_rpmnew{$_} } @{$p2r{$_}} foreach keys %p2r;
    my $sum_rpmnew = MDK::Common::Math::sum(map { int @{$p2r{$_}} } keys %p2r);
    $sum_rpmnew == 0 and return 1;

    my $appTitle = yui::YUI::app()->applicationTitle();

    ## set new title to get it in dialog
    yui::YUI::app()->setApplicationTitle($loc->N("Installation finished"));

    my $factory      = yui::YUI::widgetFactory;

    ## | [msg-label]                      |
    ## |                                  |
    ## | pkg-tree                         |
    ## |                                  |
    ## | info on selected pkg             |(1)
    ## | Remove( ) Use ( ) Do nothing (*) |
    ## |                                  |
    ## |             [ok]                 |
    ####
    # (1) info on pkg list:
    #  selected configuration file diff between rpmnew/rpmsave and used one

    my $dialog       = $factory->createPopupDialog;
    my $vbox         = $factory->createVBox( $dialog );
    my $msgBox       = $factory->createLabel($vbox, $msg, 1);
                       $factory->createVSpacing($vbox, 1);
    # Tree for groups
    my $tree         = $factory->createTree($vbox, $loc->N("Select a package"));
                       $tree->setWeight($yui::YD_VERT,10);
                       $factory->createVSpacing($vbox, 1);
    my $infoBox      = $factory->createRichText($vbox, "", 0);
                       $infoBox->setWeight($yui::YD_HORIZ, 20);
                       $infoBox->setWeight($yui::YD_VERT, 20);
                       $factory->createVSpacing($vbox, 1);
    my $radiobuttongroup = $factory->createRadioButtonGroup($vbox);
    my $rbbox = $factory->createHBox($radiobuttongroup);
    my $rdnBtn = {
        remove_rpmnew => $loc->N("Remove new file"),
        use_rpmnew    => $loc->N("Use new file"),
        do_onthing    => $loc->N("Do nothing"),
    };

    my %radiobutton    = ();
    my @rdnbtn_order   = ('remove_rpmnew', 'use_rpmnew', 'do_onthing');
    foreach my $btn_name (@rdnbtn_order) {
        $radiobutton{$btn_name} = $factory->createRadioButton($rbbox, $rdnBtn->{$btn_name});
        $radiobutton{$btn_name}->setValue(1) if $btn_name eq 'do_onthing';
        $radiobutton{$btn_name}->setNotify(1);
        $radiobuttongroup->addRadioButton($radiobutton{$btn_name});
    }
    $radiobuttongroup->setEnabled(0);
    my $hbox         = $factory->createHBox( $vbox );
    my $align        = $factory->createHCenter($hbox);
    my $okButton     = $factory->createPushButton($align,  $loc->N("Ok"));
                       $okButton->setDefaultButton(1);

    # adding packages to the list
    my $itemColl = new yui::YItemCollection;
    my $num = 0;
    my %file_action = ();
    foreach my $p (sort keys %p2r) {
        if (scalar @{$p2r{$p}}) {
            my $item = new yui::YTreeItem ("$p");
            foreach my $f (@{$p2r{$p}}) {
                my $child = new yui::YTreeItem ($item, "$f");
                $child->DISOWN();
                $file_action{$f} = 'do_onthing';
            }
            $itemColl->push($item);
            $item->DISOWN();
        }
    }

    $tree->addItems($itemColl);
    $tree->setImmediateMode(1);
    $tree->rebuildTree();

    while(1) {
        my $event     = $dialog->waitForEvent();
        my $eventType = $event->eventType();

        #event type checking
        if ($eventType == $yui::YEvent::CancelEvent) {
            last;
        }
        elsif ($eventType == $yui::YEvent::WidgetEvent) {
            ### widget
            my $widget = $event->widget();
            if ($widget == $tree) {
                #change info
                my $item = $tree->selectedItem();
                if ($item && !$item->hasChildren()) {
                    my $filename = $tree->currentItem()->label();
                    _performDiff($filename, $infoBox);
                    $radiobuttongroup->setEnabled(1);
                    #$radiobuttongroup->uncheckOtherButtons ($radiobutton{$file_action{$filename}});
                    yui::YUI::ui()->blockEvents();
                    $radiobutton{$file_action{$filename}}->setValue(1);
                    yui::YUI::ui()->unblockEvents();
                }
                else {
                    $infoBox->setValue("");
                    $radiobuttongroup->setEnabled(0);
                }
            }
            elsif ($widget == $okButton) {
                # TODO
                foreach my $file (keys %file_action) {
                    my $rpmnew = _rpmnewFile($file);
                    if ($file_action{$file} eq 'remove_rpmnew') {
                       eval { unlink "$rpmnew"};
                    }
                    elsif ($file_action{$file} eq 'use_rpmnew') {
                        MDK::Common::File::renamef($rpmnew, $file);
                    }
                    # else do_onthing
                }
                last;
            }
            else {
                # radio buttons
                RDNBTN: foreach my $btn_name (@rdnbtn_order) {
                    if ($widget == $radiobutton{$btn_name}) {
                        my $filename = $tree->currentItem()->label();
                        $file_action{$filename} = $btn_name;
                        last RDNBTN;
                    }
                }
            }
        }
    }

    destroy $dialog;

    # restore original title
    yui::YUI::app()->setApplicationTitle($appTitle) if $appTitle;

    return 0;
}


#=============================================================

=head2 do_merge_if_needed

=head3 DESCRIPTION

    This function look for new configuration file versions
    and ask for actions using the rpmnew_dialog

=cut

#=============================================================
sub do_merge_if_needed() {
    if ($rpmdragora_options{'merge-all-rpmnew'}) {
        my %pkg2rpmnew;
        my $wait = wait_msg($loc->N("Please wait, searching..."));
        print "Searching .rpmnew and .rpmsave files...\n";
        # costly:
        open_rpm_db()->traverse(sub {
                          my $n = my_fullname($_[0]);
                          $pkg2rpmnew{$n} = [ grep { m|^/etc| && (-r "$_.rpmnew" || -r "$_.rpmsave") } map { chomp_($_) } $_[0]->conf_files ];
                      });
        print "done.\n";
        remove_wait_msg($wait);

        rpmnew_dialog('', %pkg2rpmnew) and print "Nothing to do.\n";
    }

    return;
}

1;
