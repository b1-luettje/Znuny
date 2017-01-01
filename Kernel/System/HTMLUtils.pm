# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::HTMLUtils;

use strict;
use warnings;

use utf8;

use MIME::Base64;
use HTML::Truncate;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Encode',
    'Kernel::System::Log',
);

=head1 NAME

Kernel::System::HTMLUtils - creating and modifying html strings

=head1 SYNOPSIS

A module for creating and modifying html strings.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object. Do not use it directly, instead use:

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $HTMLUtilsObject = $Kernel::OM->Get('Kernel::System::HTMLUtils');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get debug level from parent
    $Self->{Debug} = $Param{Debug} || 0;

    return $Self;
}

=item ToAscii()

convert a html string to an ascii string

    my $Ascii = $HTMLUtilsObject->ToAscii( String => $String );

=cut

sub ToAscii {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(String)) {
        if ( !defined $Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # turn on utf8 flag (bug#10970, bug#11596 and bug#12097)
    $Kernel::OM->Get('Kernel::System::Encode')->EncodeInput( \$Param{String} );

    # get length of line for forcing line breakes
    my $LineLength = $Self->{'Ticket::Frontend::TextAreaNote'} || 78;

    # find <a href=....> and replace it with [x]
    my $LinkList = '';
    my $Counter  = 0;
    $Param{String} =~ s{
        <a\s.*?href=("|')(.+?)("|').*?>
    }
    {
        my $Link = $2;
        $Counter++;
        $LinkList .= "[$Counter] $Link\n";
        "[$Counter]";
    }egxi;

    # pre-process <blockquote> and <div style=\"cite\"
    my %Cite;
    $Counter = 0;
    $Param{String} =~ s{
        <blockquote(.*?)>(.+?)</blockquote>
    }
    {
        my $Ascii = $Self->ToAscii(
            String => $2,
        );
        # force line breaking
        if ( length $Ascii > $LineLength ) {
            $Ascii =~ s/(.{4,$LineLength})(?:\s|\z)/$1\n/gm;
        }
        $Ascii =~ s/^(.*?)$/> $1/gm;
        $Counter++;
        my $Key     = "######Cite::$Counter######";
        $Cite{$Key} = $Ascii;
        $Key;
    }segxmi;
    $Param{String} =~ s{
        <div\s{1,5}type="cite".+?>(.+?)</div>
    }
    {
        my $Ascii = $Self->ToAscii(
            String => $1,
        );
        # force line breaking
        if ( length $Ascii > $LineLength ) {
            $Ascii =~ s/(.{4,$LineLength})(?:\s|\z)/$1\n/gm;
        }
        $Ascii =~ s/^(.*?)$/> $1/gm;
        $Counter++;
        my $Key     = "######Cite::$Counter######";
        $Cite{$Key} = $Ascii;
        $Key;
    }segxmi;

    # remember <pre> and <code> tags
    my %One2One;
    $Counter = 0;
    $Param{String} =~ s{
        <(pre|code)(.*?)>(.+?)</(pre|code)(.*?)>
    }
    {
        my $Content = $3;
        $Counter++;
        my $Key        = "######One2One::$Counter######";
        $One2One{$Key} = $Content;
        $Key;
    }segxmi;

    # remove comments at the first place to avoid to much work
    # for the regex engine
    $Param{String} =~ s{<!-- .*? -->}{}xmgsi;

    # remove empty lines
    $Param{String} =~ s/^\s*//mg;

    # fix some bad stuff from opera and others
    $Param{String} =~ s/(\n\r|\r\r\n|\r\n)/\n/gs;

    # remove new line after <br>
    $Param{String} =~ s/(\<br(\s{0,3}|\s{1,3}.+?)(\/|)\>)(\n|\r)/$1/gsi;

    # replace new lines with one space
    $Param{String} =~ s/\n/ /gs;
    $Param{String} =~ s/\r/ /gs;

    # remove style tags
    $Param{String} =~ s{<style [^>]*? />}{}xgsi;
    $Param{String} =~ s{<style [^>]*? > .*? </style[^>]*>}{}xgsi;

    # remove <br>,<br/>,<br />, <br class="name"/>, tags and replace it with \n
    $Param{String} =~ s/\<br(\s{0,3}|\s{1,3}.+?)(\/|)\>/\n/gsi;

    # remove </div> tags and replace it with \n
    $Param{String} =~ s/<\/(\s{0,3})div>/\n/gsi;

    # remove hr tags and replace it with \n
    $Param{String} =~ s/\<(hr|hr.+?)\>/\n\n/gsi;

    # remove p, table tags and replace it with \n
    $Param{String} =~ s/\<(\/|)(p|p.+?|table|table.+?)\>/\n\n/gsi;

    # remove opening tr, th tags and replace them with \n
    $Param{String} =~ s/\<(tr|tr.+?|th|th.+?)\>/\n\n/gsi;

    # convert li tags to \n -
    $Param{String} =~ s/\<li\>/\n - /gsi;

    # convert </ul> and </ol> tags to \n\n
    $Param{String} =~ s/\<\/(ul|ol)\>/\n\n/gsi;

    # remove </td> tags and replace them with " "
    $Param{String} =~ s/<\/td[^>]*>/ /gsi;

    # replace multiple spaces with just one space
    $Param{String} =~ s/[ ]{2,}/ /mg;

    # remember <pre> and <code> tags and replace it
    for my $Key ( sort keys %One2One ) {
        $Param{String} =~ s/$Key/\n\n\n$One2One{$Key}\n\n/g;
    }

    # strip all other tags
    $Param{String} =~ s/\<.+?\>//gs;

    # html encode based on cpan's HTML::Entities v1.35
    my %Entity = (

        # Some normal chars that have special meaning in SGML context
        amp  => '&',    # ampersand
        'gt' => '>',    # greater than
        'lt' => '<',    # less than
        quot => '"',    # double quote
        apos => "'",    # single quote

        # PUBLIC ISO 8879-1986//ENTITIES Added Latin 1//EN//HTML
        AElig  => chr(198),    # capital AE diphthong (ligature)
        Aacute => chr(193),    # capital A, acute accent
        Acirc  => chr(194),    # capital A, circumflex accent
        Agrave => chr(192),    # capital A, grave accent
        Aring  => chr(197),    # capital A, ring
        Atilde => chr(195),    # capital A, tilde
        Auml   => chr(196),    # capital A, dieresis or umlaut mark
        Ccedil => chr(199),    # capital C, cedilla
        ETH    => chr(208),    # capital Eth, Icelandic
        Eacute => chr(201),    # capital E, acute accent
        Ecirc  => chr(202),    # capital E, circumflex accent
        Egrave => chr(200),    # capital E, grave accent
        Euml   => chr(203),    # capital E, dieresis or umlaut mark
        Iacute => chr(205),    # capital I, acute accent
        Icirc  => chr(206),    # capital I, circumflex accent
        Igrave => chr(204),    # capital I, grave accent
        Iuml   => chr(207),    # capital I, dieresis or umlaut mark
        Ntilde => chr(209),    # capital N, tilde
        Oacute => chr(211),    # capital O, acute accent
        Ocirc  => chr(212),    # capital O, circumflex accent
        Ograve => chr(210),    # capital O, grave accent
        Oslash => chr(216),    # capital O, slash
        Otilde => chr(213),    # capital O, tilde
        Ouml   => chr(214),    # capital O, dieresis or umlaut mark
        THORN  => chr(222),    # capital THORN, Icelandic
        Uacute => chr(218),    # capital U, acute accent
        Ucirc  => chr(219),    # capital U, circumflex accent
        Ugrave => chr(217),    # capital U, grave accent
        Uuml   => chr(220),    # capital U, dieresis or umlaut mark
        Yacute => chr(221),    # capital Y, acute accent
        aacute => chr(225),    # small a, acute accent
        acirc  => chr(226),    # small a, circumflex accent
        aelig  => chr(230),    # small ae diphthong (ligature)
        agrave => chr(224),    # small a, grave accent
        aring  => chr(229),    # small a, ring
        atilde => chr(227),    # small a, tilde
        auml   => chr(228),    # small a, dieresis or umlaut mark
        ccedil => chr(231),    # small c, cedilla
        eacute => chr(233),    # small e, acute accent
        ecirc  => chr(234),    # small e, circumflex accent
        egrave => chr(232),    # small e, grave accent
        eth    => chr(240),    # small eth, Icelandic
        euml   => chr(235),    # small e, dieresis or umlaut mark
        iacute => chr(237),    # small i, acute accent
        icirc  => chr(238),    # small i, circumflex accent
        igrave => chr(236),    # small i, grave accent
        iuml   => chr(239),    # small i, dieresis or umlaut mark
        ntilde => chr(241),    # small n, tilde
        oacute => chr(243),    # small o, acute accent
        ocirc  => chr(244),    # small o, circumflex accent
        ograve => chr(242),    # small o, grave accent
        oslash => chr(248),    # small o, slash
        otilde => chr(245),    # small o, tilde
        ouml   => chr(246),    # small o, dieresis or umlaut mark
        szlig  => chr(223),    # small sharp s, German (sz ligature)
        thorn  => chr(254),    # small thorn, Icelandic
        uacute => chr(250),    # small u, acute accent
        ucirc  => chr(251),    # small u, circumflex accent
        ugrave => chr(249),    # small u, grave accent
        uuml   => chr(252),    # small u, dieresis or umlaut mark
        yacute => chr(253),    # small y, acute accent
        yuml   => chr(255),    # small y, dieresis or umlaut mark

        # Some extra Latin 1 chars that are listed in the HTML3.2 draft (21-May-96)
        copy => chr(169),      # copyright sign
        reg  => chr(174),      # registered sign
        nbsp => chr(160),      # non breaking space

        # Additional ISO-8859/1 entities listed in rfc1866 (section 14)
        iexcl   => chr(161),
        cent    => chr(162),
        pound   => chr(163),
        curren  => chr(164),
        yen     => chr(165),
        brvbar  => chr(166),
        sect    => chr(167),
        uml     => chr(168),
        ordf    => chr(170),
        laquo   => chr(171),
        'not'   => chr(172),    # not is a keyword in perl
        shy     => chr(173),
        macr    => chr(175),
        deg     => chr(176),
        plusmn  => chr(177),
        sup1    => chr(185),
        sup2    => chr(178),
        sup3    => chr(179),
        acute   => chr(180),
        micro   => chr(181),
        para    => chr(182),
        middot  => chr(183),
        cedil   => chr(184),
        ordm    => chr(186),
        raquo   => chr(187),
        frac14  => chr(188),
        frac12  => chr(189),
        frac34  => chr(190),
        iquest  => chr(191),
        'times' => chr(215),    # times is a keyword in perl
        divide  => chr(247),

        (
            $] > 5.007
            ? (
                OElig    => chr(338),
                oelig    => chr(339),
                Scaron   => chr(352),
                scaron   => chr(353),
                Yuml     => chr(376),
                fnof     => chr(402),
                circ     => chr(710),
                tilde    => chr(732),
                Alpha    => chr(913),
                Beta     => chr(914),
                Gamma    => chr(915),
                Delta    => chr(916),
                Epsilon  => chr(917),
                Zeta     => chr(918),
                Eta      => chr(919),
                Theta    => chr(920),
                Iota     => chr(921),
                Kappa    => chr(922),
                Lambda   => chr(923),
                Mu       => chr(924),
                Nu       => chr(925),
                Xi       => chr(926),
                Omicron  => chr(927),
                Pi       => chr(928),
                Rho      => chr(929),
                Sigma    => chr(931),
                Tau      => chr(932),
                Upsilon  => chr(933),
                Phi      => chr(934),
                Chi      => chr(935),
                Psi      => chr(936),
                Omega    => chr(937),
                alpha    => chr(945),
                beta     => chr(946),
                gamma    => chr(947),
                delta    => chr(948),
                epsilon  => chr(949),
                zeta     => chr(950),
                eta      => chr(951),
                theta    => chr(952),
                iota     => chr(953),
                kappa    => chr(954),
                lambda   => chr(955),
                mu       => chr(956),
                nu       => chr(957),
                xi       => chr(958),
                omicron  => chr(959),
                pi       => chr(960),
                rho      => chr(961),
                sigmaf   => chr(962),
                sigma    => chr(963),
                tau      => chr(964),
                upsilon  => chr(965),
                phi      => chr(966),
                chi      => chr(967),
                psi      => chr(968),
                omega    => chr(969),
                thetasym => chr(977),
                upsih    => chr(978),
                piv      => chr(982),
                ensp     => chr(8194),
                emsp     => chr(8195),
                thinsp   => chr(8201),
                zwnj     => chr(8204),
                zwj      => chr(8205),
                lrm      => chr(8206),
                rlm      => chr(8207),
                ndash    => chr(8211),
                mdash    => chr(8212),
                lsquo    => chr(8216),
                rsquo    => chr(8217),
                sbquo    => chr(8218),
                ldquo    => chr(8220),
                rdquo    => chr(8221),
                bdquo    => chr(8222),
                dagger   => chr(8224),
                Dagger   => chr(8225),
                bull     => chr(8226),
                hellip   => chr(8230),
                permil   => chr(8240),
                prime    => chr(8242),
                Prime    => chr(8243),
                lsaquo   => chr(8249),
                rsaquo   => chr(8250),
                oline    => chr(8254),
                frasl    => chr(8260),
                euro     => chr(8364),
                image    => chr(8465),
                weierp   => chr(8472),
                real     => chr(8476),
                trade    => chr(8482),
                alefsym  => chr(8501),
                larr     => chr(8592),
                uarr     => chr(8593),
                rarr     => chr(8594),
                darr     => chr(8595),
                harr     => chr(8596),
                crarr    => chr(8629),
                lArr     => chr(8656),
                uArr     => chr(8657),
                rArr     => chr(8658),
                dArr     => chr(8659),
                hArr     => chr(8660),
                forall   => chr(8704),
                part     => chr(8706),
                exist    => chr(8707),
                empty    => chr(8709),
                nabla    => chr(8711),
                isin     => chr(8712),
                notin    => chr(8713),
                ni       => chr(8715),
                prod     => chr(8719),
                sum      => chr(8721),
                minus    => chr(8722),
                lowast   => chr(8727),
                radic    => chr(8730),
                prop     => chr(8733),
                infin    => chr(8734),
                ang      => chr(8736),
                'and'    => chr(8743),
                'or'     => chr(8744),
                cap      => chr(8745),
                cup      => chr(8746),
                'int'    => chr(8747),
                there4   => chr(8756),
                sim      => chr(8764),
                cong     => chr(8773),
                asymp    => chr(8776),
                'ne'     => chr(8800),
                equiv    => chr(8801),
                'le'     => chr(8804),
                'ge'     => chr(8805),
                'sub'    => chr(8834),
                sup      => chr(8835),
                nsub     => chr(8836),
                sube     => chr(8838),
                supe     => chr(8839),
                oplus    => chr(8853),
                otimes   => chr(8855),
                perp     => chr(8869),
                sdot     => chr(8901),
                lceil    => chr(8968),
                rceil    => chr(8969),
                lfloor   => chr(8970),
                rfloor   => chr(8971),
                lang     => chr(9001),
                rang     => chr(9002),
                loz      => chr(9674),
                spades   => chr(9824),
                clubs    => chr(9827),
                hearts   => chr(9829),
                diams    => chr(9830),
                )
            : ()
            )
    );

    # encode html entities like "&#8211;"
    $Param{String} =~ s{
        (&\#(\d+);?)
    }
    {
        my $Chr = chr( $2 );

        # Make sure we get valid UTF8 code points, but skip characters from 128 to 255
        #   (inclusive), since they are by default internally not encoded as UTF-8 for
        #   backward compatibility reasons. See bug#12457 for more information.
        if ( $2 < 128 || $2 > 255 ) {
            Encode::_utf8_off($Chr);
            $Chr = Encode::decode('utf-8', $Chr, 0);
        }

        if ( $Chr ) {
            $Chr;
        }
        else {
            $1;
        };
    }egx;

    # encode html entities like "&#x3d;"
    $Param{String} =~ s{
        (&\#[xX]([0-9a-fA-F]+);?)
    }
    {
        my $ChrOrig = $1;
        my $Dec = hex( $2 );
        if ( $Dec ) {
            my $Chr = chr( $Dec );

            # Make sure we get valid UTF8 code points, but skip characters from 128 to 255
            #   (inclusive), since they are by default internally not encoded as UTF-8 for
            #   backward compatibility reasons. See bug#12457 for more information.
            if ( $Dec < 128 || $Dec > 255 ) {
                Encode::_utf8_off($Chr);
                $Chr = Encode::decode('utf-8', $Chr, 0);
            }

            if ( $Chr ) {
                $Chr;
            }
            else {
                $ChrOrig;
            }
        }
        else {
            $ChrOrig;
        }
    }egx;

    # encode html entities like "&amp;"
    $Param{String} =~ s{
        (&(\w+);?)
    }
    {
        if ( $Entity{$2} ) {
            $Entity{$2};
        }
        else {
            $1;
        }
    }egx;

    # remove empty lines
    $Param{String} =~ s/^\s*\n\s*\n/\n/mg;

    # force line breaking
    if ( length $Param{String} > $LineLength ) {
        $Param{String} =~ s/(.{4,$LineLength})(?:\s|\z)/$1\n/gm;
    }

    # remember <blockquote> and <div style=\"cite\"
    for my $Key ( sort keys %Cite ) {
        $Param{String} =~ s/$Key/$Cite{$Key}\n/g;
    }

    # add extracted links
    if ($LinkList) {
        $Param{String} .= "\n\n" . $LinkList;
    }

    return $Param{String};
}

=item ToHTML()

convert an ascii string to a html string

    my $HTMLString = $HTMLUtilsObject->ToHTML( String => $String );

=cut

sub ToHTML {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(String)) {
        if ( !defined $Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # fix some bad stuff from opera and others
    $Param{String} =~ s/(\n\r|\r\r\n|\r\n)/\n/gs;

    $Param{String} =~ s/&/&amp;/g;
    $Param{String} =~ s/</&lt;/g;
    $Param{String} =~ s/>/&gt;/g;
    $Param{String} =~ s/"/&quot;/g;
    $Param{String} =~ s/(\n|\r)/<br\/>\n/g;
    $Param{String} =~ s/  /&nbsp;&nbsp;/g;

    return $Param{String};
}

=item DocumentComplete()

check and e. g. add <html> and <body> tags to given html string

    my $HTMLDocument = $HTMLUtilsObject->DocumentComplete(
        String  => $String,
        Charset => $Charset,
    );

=cut

sub DocumentComplete {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(String Charset)) {
        if ( !defined $Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    return $Param{String} if $Param{String} =~ /<html>/i;

    my $Css = $Kernel::OM->Get('Kernel::Config')->Get('Frontend::RichText::DefaultCSS')
        || 'font-size: 12px; font-family:Courier,monospace,fixed;';

    # Use the HTML5 doctype because it is compatible with HTML4 and causes the browsers
    #   to render the content in standards mode, which is more safe than quirks mode.
    my $Body = '<!DOCTYPE html><html><head>';
    $Body
        .= '<meta http-equiv="Content-Type" content="text/html; charset=' . $Param{Charset} . '"/>';
    $Body .= '</head><body style="' . $Css . '">' . $Param{String} . '</body></html>';
    return $Body;
}

=item DocumentStrip()

remove html document tags from string

    my $HTMLString = $HTMLUtilsObject->DocumentStrip(
        String  => $String,
    );

=cut

sub DocumentStrip {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(String)) {
        if ( !defined $Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    $Param{String} =~ s/^<\!DOCTYPE\s+HTML.+?>//gsi;
    $Param{String} =~ s/<head>.+?<\/head>//gsi;
    $Param{String} =~ s/<(html|body)(.*?)>//gsi;
    $Param{String} =~ s/<\/(html|body)>//gsi;

    return $Param{String};
}

=item DocumentCleanup()

perform some sanity checks on HTML content.

 -  Replace MS Word 12 <p|div> with class "MsoNormal" by using <br/> because
    it's not used as <p><div> (margin:0cm; margin-bottom:.0001pt;).

 -  Replace <blockquote> by using
    "<div style="border:none;border-left:solid blue 1.5pt;padding:0cm 0cm 0cm 4.0pt" type="cite">"
    because of cross mail client and browser compatibility.

 -  If there is no HTML doctype present, inject the HTML5 doctype, because it is compatible with HTML4
    and causes the browsers to render the content in standards mode, which is safer.

    $HTMLBody = $HTMLUtilsObject->DocumentCleanup(
        String => $HTMLBody,
    );

=cut

sub DocumentCleanup {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(String)) {
        if ( !defined $Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # If the string starts with <html> directly, inject the doctype
    $Param{String} =~ s{ \A \s* <html }{<!DOCTYPE html><html}gsmix;

    # remove <base> tags - see bug#8880
    $Param{String} =~ s{<base .*?>}{}xmsi;

    # replace MS Word 12 <p|div> with class "MsoNormal" by using <br/> because
    # it's not used as <p><div> (margin:0cm; margin-bottom:.0001pt;)
    $Param{String} =~ s{
        <p\s{1,3}class=(|"|')MsoNormal(|"|')(.*?)>(.+?)</p>
    }
    {
        $4 . '<br/>';
    }segxmi;

    $Param{String} =~ s{
        <div\s{1,3}class=(|"|')MsoNormal(|"|')(.*?)>(.+?)</div>
    }
    {
        $4 . '<br/>';
    }segxmi;

    # replace <blockquote> by using
    # "<div style="border:none;border-left:solid blue 1.5pt;padding:0cm 0cm 0cm 4.0pt" type="cite">"
    # because of cross mail client and browser compatability
    my $Style = "border:none;border-left:solid blue 1.5pt;padding:0cm 0cm 0cm 4.0pt";
    for ( 1 .. 10 ) {
        $Param{String} =~ s{
            <blockquote(.*?)>(.+?)</blockquote>
        }
        {
            "<div $1 style=\"$Style\">$2</div>";
        }segxmi;
    }

    return $Param{String};
}

=item LinkQuote()

URL link detections in HTML code, add "<a href" if missing

    my $HTMLWithLinks = $HTMLUtilsObject->LinkQuote(
        String    => $HTMLString,
        Target    => 'TargetName', # content of target="?", e. g. _blank
        TargetAdd => 1,            # add target="_blank" to all existing "<a href"
    );

also string ref is possible

    my $HTMLWithLinksRef = $HTMLUtilsObject->LinkQuote(
        String => \$HTMLStringRef,
    );

=cut

sub LinkQuote {
    my ( $Self, %Param ) = @_;

    my $String = $Param{String} || '';

    # check ref
    my $StringScalar;
    if ( !ref $String ) {
        $StringScalar = $String;
        $String       = \$StringScalar;

        # return if string is not a ref and it is empty
        return $StringScalar if !$StringScalar;
    }

    # add target to already existing url of html string
    if ( $Param{TargetAdd} ) {

        # find target
        my $Target = $Param{Target};
        if ( !$Target ) {
            $Target = '_blank';
        }

        # add target to existing "<a href"
        ${$String} =~ s{
            (<a\s{1,10})([^>]+)>
        }
        {
            my $Start = $1;
            my $Value = $2;
            if ( $Value !~ /href=/i || $Value =~ /target=/i ) {
                "$Start$Value>";
            }
            else {
                "$Start$Value target=\"$Target\">";
            }
        }egxsi;
    }

    my $Marker = "§" x 10;

    # Remove existing <a>...</a> tags and their content to be re-inserted later, this must not be quoted.
    # Also remove other tags to avoid quoting in tag parameters.
    my $Counter = 0;
    my %TagHash;
    ${$String} =~ s{
        (<a\s[^>]*?>[^>]*</a>|<[^>]+?>)
    }
    {
        my $Content = $1;
        my $Key     = "${Marker}TagHash-$Counter${Marker}";
        $TagHash{$Counter++} = $Content;
        $Key;
    }egxism;

    # Add <a> tags for URLs in the content.
    my $Target = '';
    if ( $Param{Target} ) {
        $Target = " target=\"$Param{Target}\"";
    }
    ${$String} =~ s{
        (                                          # $1 greater-than and less-than sign
            > | < | \s+ | §{10} |
            (?: &[a-zA-Z0-9]+; )                   # get html entities
        )
        (                                          # $2
            (?:                                    # http or only www
                (?: (?: http s? | ftp ) :\/\/) |   # http://,https:// and ftp://
                (?: (?: www | ftp ) \.)            # www. and ftp.
            )
        )
        (                                          # $3
            (?: [a-z0-9\-]+ \. )*                  # get subdomains, optional
            [a-z0-9\-]+                            # get top level domain
            (?:                                    # optional port number
                [:]
                [0-9]+
            )?
            (?:                                    # file path element
                [\/\.]
                | [a-zA-Z0-9\-_=%]
            )*
            (?:                                    # param string
                [\?]                               # if param string is there, "?" must be present
                [a-zA-Z0-9&;=%\-_:\.\/]*           # param string content, this will also catch entities like &amp;
            )?
            (?:                                    # link hash string
                [\#]                               #
                [a-zA-Z0-9&;=%\-_:\.\/]*           # hash string content, this will also catch entities like &amp;
            )?
        )
        (?=                                        # $4
            (?:
                [\?,;!\.\)] (?: \s | $ )           # \)\s this construct is because of bug# 2450
                | \"
                | \]
                | \s+
                | '
                | >                               # greater-than and less-than sign
                | <                               # "
                | (?: &[a-zA-Z0-9]+; )+            # html entities
                | $                                # bug# 2715
            )
            | §{10}                                # ending TagHash
        )
    }
    {
        my $Start    = $1;
        my $Protocol = $2;
        my $Link     = $3;
        my $End      = $4 || '';

        # there may different links for href and link body
        my $HrefLink;
        my $DisplayLink;

        if ( $Protocol =~ m{\A ( http | https | ftp ) : \/ \/ }xi ) {
            $DisplayLink = $Protocol . $Link;
            $HrefLink    = $DisplayLink;
        }
        else {
            if ($Protocol =~ m{\A ftp }smx ) {
                $HrefLink = 'ftp://';
            }
            else {
                $HrefLink = 'http://';
            }

            if ( $Protocol ) {
                $HrefLink   .= $Protocol;
                $DisplayLink = $Protocol;
            }

            $DisplayLink .= $Link;
            $HrefLink    .= $Link;
        }
        $Start . "<a href=\"$HrefLink\"$Target title=\"$HrefLink\">$DisplayLink<\/a>" . $End;
    }egxism;

    # Re-add previously removed tags.
    ${$String} =~ s{${Marker}TagHash-(\d+)${Marker}}{$TagHash{$1}}egsxim;

    # check ref && return result like called
    if ($StringScalar) {
        return ${$String};
    }
    return $String;
}

=item Safety()

To remove/strip active html tags/addons (javascript, applets, embeds and objects)
from html strings.

    my %Safe = $HTMLUtilsObject->Safety(
        String         => $HTMLString,
        NoApplet       => 1,
        NoObject       => 1,
        NoEmbed        => 1,
        NoSVG          => 1,
        NoImg          => 1,
        NoIntSrcLoad   => 0,
        NoExtSrcLoad   => 1,
        NoJavaScript   => 1,
        ReplacementStr => 'string',          # optional, string to show instead of applet, object, embed, svg and img tags
    );

also string ref is possible

    my %Safe = $HTMLUtilsObject->Safety(
        String       => \$HTMLStringRef,
        NoApplet     => 1,
        NoObject     => 1,
        NoEmbed      => 1,
        NoSVG        => 1,
        NoImg        => 1,
        NoIntSrcLoad => 0,
        NoExtSrcLoad => 1,
        NoJavaScript => 1,
    );

returns

    my %Safe = (
        String  => $HTMLString, # modified html string (scalar or ref)
        Replace => 1,           # info if something got replaced
    );

=cut

sub Safety {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(String)) {
        if ( !defined $Param{$_} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    my $String = $Param{String} || '';

    # check ref
    my $StringScalar;
    if ( !ref $String ) {
        $StringScalar = $String;
        $String       = \$StringScalar;
    }

    my %Safety;

    my $Replaced;

    # In UTF-7, < and > can be encoded to mask them from security filters like this one.
    my $TagStart = '(?:<|[+]ADw-)';
    my $TagEnd   = '(?:>|[+]AD4-)';

    # This can also be entity-encoded to hide it from the parser.
    #   Browsers seem to tolerate an omitted ";".
    my $JavaScriptPrefixRegex = '
        (?: j | &\#106[;]? | &\#x6a[;]? )
        (?: a | &\#97[;]?  | &\#x61[;]? )
        (?: v | &\#118[;]? | &\#x76[;]? )
        (?: a | &\#97[;]?  | &\#x61[;]? )
        (?: s | &\#115[;]? | &\#x73[;]? )
        (?: c | &\#99[;]?  | &\#x63[;]? )
        (?: r | &\#114[;]? | &\#x72[;]? )
        (?: i | &\#105[;]? | &\#x69[;]? )
        (?: p | &\#112[;]? | &\#x70[;]? )
        (?: t | &\#116[;]? | &\#x74[;]? )
    ';

    my $ExpressionPrefixRegex = '
        (?: e | &\#101[;]? | &\#x65[;]? )
        (?: x | &\#120[;]? | &\#x78[;]? )
        (?: p | &\#112[;]? | &\#x70[;]? )
        (?: r | &\#114[;]? | &\#x72[;]? )
        (?: e | &\#101[;]? | &\#x65[;]? )
        (?: s | &\#115[;]? | &\#x73[;]? )
        (?: s | &\#115[;]? | &\#x73[;]? )
        (?: i | &\#105[;]? | &\#x69[;]? )
        (?: o | &\#111[;]? | &\#x6f[;]? )
        (?: n | &\#110[;]? | &\#x6e[;]? )
    ';

    # Replace as many times as it is needed to avoid nesting tag attacks.
    do {
        $Replaced = undef;

        # remove script tags
        if ( $Param{NoJavaScript} ) {
            $Replaced += ${$String} =~ s{
                $TagStart script.*? $TagEnd .*?  $TagStart /script \s* $TagEnd
            }
            {}sgxim;
            $Replaced += ${$String} =~ s{
                $TagStart script.*? $TagEnd .+? ($TagStart|$TagEnd)
            }
            {}sgxim;

            # remove style/javascript parts
            $Replaced += ${$String} =~ s{
                $TagStart style[^>]+? $JavaScriptPrefixRegex (.+?|) $TagEnd (.*?) $TagStart /style \s* $TagEnd
            }
            {}sgxim;

            # remove MS CSS expressions (JavaScript embedded in CSS)
            ${$String} =~ s{
                ($TagStart style[^>]+? $TagEnd .*? $TagStart /style \s* $TagEnd)
            }
            {
                if ( index($1, 'expression(' ) > -1 ) {
                    $Replaced = 1;
                    '';
                }
                else {
                    $1;
                }
            }egsxim;
        }

        # remove HTTP redirects
        $Replaced += ${$String} =~ s{
            $TagStart meta [^>]+? http-equiv=('|"|)refresh [^>]+? $TagEnd
        }
        {}sgxim;

        my $ReplacementStr = $Param{ReplacementStr} // '';

        # remove <applet> tags
        if ( $Param{NoApplet} ) {
            $Replaced += ${$String} =~ s{
                $TagStart applet.*? $TagEnd (.*?) $TagStart /applet \s* $TagEnd
            }
            {$ReplacementStr}sgxim;
        }

        # remove <Object> tags
        if ( $Param{NoObject} ) {
            $Replaced += ${$String} =~ s{
                $TagStart object.*? $TagEnd (.*?) $TagStart /object \s* $TagEnd
            }
            {$ReplacementStr}sgxim;
        }

        # remove <svg> tags
        if ( $Param{NoSVG} ) {
            $Replaced += ${$String} =~ s{
                $TagStart svg.*? $TagEnd (.*?) $TagStart /svg \s* $TagEnd
            }
            {$ReplacementStr}sgxim;
        }

        # remove <img> tags
        if ( $Param{NoImg} ) {
            $Replaced += ${$String} =~ s{
                $TagStart img.*? (.*?) \s* $TagEnd
            }
            {$ReplacementStr}sgxim;
        }

        # remove <embed> tags
        if ( $Param{NoEmbed} ) {
            $Replaced += ${$String} =~ s{
                $TagStart embed.*? $TagEnd
            }
            {$ReplacementStr}sgxim;
        }

        # check each html tag
        ${$String} =~ s{
            ($TagStart.+?$TagEnd)
        }
        {
            my $Tag = $1;
            if ($Param{NoJavaScript}) {

                # remove on action attributes
                $Replaced += $Tag =~ s{
                    (?:\s|/) on[a-z]+\s*=("[^"]+"|'[^']+'|.+?)($TagEnd|\s)
                }
                {$2}sgxim;

                # remove javascript in a href links or src links
                $Replaced += $Tag =~ s{
                    ((?:\s|;|/)(?:background|url|src|href)=)
                    ('|"|)                                  # delimiter, can be empty
                    (?:\s* $JavaScriptPrefixRegex .*?)      # javascript, followed by anything but the delimiter
                    \2                                      # delimiter again
                    (\s|$TagEnd)
                }
                {
                    "$1\"\"$3";
                }sgxime;

                # remove link javascript tags
                $Replaced += $Tag =~ s{
                    ($TagStart link .+? $JavaScriptPrefixRegex (.+?|) $TagEnd)
                }
                {}sgxim;

                # remove MS CSS expressions (JavaScript embedded in CSS)
                $Replaced += $Tag =~ s{
                    \sstyle=("|')[^\1]*? $ExpressionPrefixRegex [(].*?\1($TagEnd|\s)
                }
                {
                    $2;
                }egsxim;
            }

            # remove load tags
            if ($Param{NoIntSrcLoad} || $Param{NoExtSrcLoad}) {
                $Tag =~ s{
                    ($TagStart (.+?) (?: \s | /) src=(.+?) (\s.+?|) $TagEnd)
                }
                {
                    my $URL = $3;
                    if ($Param{NoIntSrcLoad} || ($Param{NoExtSrcLoad} && $URL =~ /(http|ftp|https):\//i)) {
                        $Replaced = 1;
                        '';
                    }
                    else {
                        $1;
                    }
                }segxim;
            }

            # replace original tag with clean tag
            $Tag;
        }segxim;

        $Safety{Replace} += $Replaced;

    } while ($Replaced);    ## no critic

    # check ref && return result like called
    if ($StringScalar) {
        $Safety{String} = ${$String};
    }
    else {
        $Safety{String} = $String;
    }
    return %Safety;
}

=item EmbeddedImagesExtract()

extracts embedded images with data-URLs from an HTML document.

    $HTMLUtilsObject->EmbeddedImagesExtract(
        DocumentRef    => \$Body,
        AttachmentsRef => \@Attachments,
    );

Returns nothing. If embedded images were found, these will be appended
to the attachments list, and the image data URL will be replaced with a
cid: URL in the document.

=cut

sub EmbeddedImagesExtract {
    my ( $Self, %Param ) = @_;

    if ( ref $Param{DocumentRef} ne 'SCALAR' || !defined ${ $Param{DocumentRef} } ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need DocumentRef!"
        );
        return;
    }
    if ( ref $Param{AttachmentsRef} ne 'ARRAY' ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need AttachmentsRef!"
        );
        return;
    }

    my $FQDN = $Kernel::OM->Get('Kernel::Config')->Get('FQDN');
    ${ $Param{DocumentRef} } =~ s{(src=")(data:image/)(png|gif|jpg|jpeg|bmp)(;base64,)(.+?)(")}{

        my $Base64String = $5;

        my $FileName     = 'pasted-' . time() . '-' . int(rand(1000000)) . '.' . $3;
        my $ContentType  = "image/$3; name=\"$FileName\"";
        my $ContentID    = 'pasted.' . time() . '.' . int(rand(1000000)) . '@' . $FQDN;

        my $AttachmentData = {
            Content     => decode_base64($Base64String),
            ContentType => $ContentType,
            ContentID   => $ContentID,
            Filename    => $FileName,
            Disposition => 'inline',
        };
        push @{$Param{AttachmentsRef}}, $AttachmentData;

        # compose new image tag
        $1 . "cid:$ContentID" . $6

    }egxi;

    return 1;
}

=item HTMLTruncate()

DEPRECATED: This function will be removed in further versions of OTRS

truncate an HTML string to certain amount of characters without loosing the HTML tags, the resulting
string will contain the specified amount of text characters plus the HTML tags, and ellipsis string.

special characters like &aacute; in HTML code are considered as just one character.

    my $HTML = $HTMLUtilsObject->HTMLTruncate(
        String   => $String,
        Chars    => 123,
        Ellipsis => '...',              # optional (defaults to HTML &#8230;) string to indicate
                                        #    that the HTML was truncated until that point
        UTF8Mode => 0,                  # optional 1 or 0 (defaults to 0)
        OnSpace  => 0,                  # optional 1 or 0 (defaults to 0) if enabled, prevents to
                                        #    truncate in a middle of a word, but in the space before
    );

returns

    $HTML => 'some HTML code'           # or false in case of a failure

=cut

sub HTMLTruncate {
    my ( $Self, %Param ) = @_;

    # check needed
    for my $Needed (qw(String Chars)) {

        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # translate params for compatibility reasons with HTML::Truncate
    my %CompatibilityParams = (
        'utf8_mode' => $Param{UTF8Mode} ? 1 : 0,
        'on_space'  => $Param{OnSpace}  ? 1 : 0,
        'chars'     => $Param{Chars},
        'repair'    => 1,
    );

    if ( defined $Param{Ellipsis} ) {
        $CompatibilityParams{ellipsis} = $Param{Ellipsis};
    }

    # create new HTML truncate object (with the specified options)
    my $HTMLTruncateObject;
    eval {
        $HTMLTruncateObject = HTML::Truncate->new(%CompatibilityParams);
    };

    if ( !$HTMLTruncateObject ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Could not create HTMLTruncateObject: $@",
        );
        return;
    }

    # sanitize the string
    my %Safe = $Self->Safety(
        String         => $Param{String},
        NoApplet       => 1,
        NoObject       => 1,
        NoEmbed        => 1,
        NoSVG          => 1,
        NoImg          => 1,
        NoIntSrcLoad   => 1,
        NoExtSrcLoad   => 1,
        NoJavaScript   => 1,
        ReplacementStr => '✂︎',
    );

    # truncate the HTML input string
    my $Result;
    if ( !eval { $Result = $HTMLTruncateObject->truncate( $Safe{String} ) } ) {

        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Truncating string failed: ' . $@,
        );

        return;
    }

    return $Result;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
