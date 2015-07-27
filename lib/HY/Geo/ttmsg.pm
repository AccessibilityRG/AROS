package HY::Geo::ttmsg;

use strict;

use Net::SMS::BulkSMS;
use MIME::Lite;
use MIME::Base64;

=encoding utf8

=head1 SYNOPSIS

use HY::Geo::ttmsg;

=head1 DESCRIPTION

HY::Geo::ttmsg sends notification messages by SMS or email. The SMS
messages are sent using C<Net::SMS::BulkSMS> and for emails it uses
C<MIME::Lite>.

=head1 METHODS

=over 4

=item new

Creates the ttmsg object.

 my $ttmsg1 = HY::Geo::ttmsg(SMTP=>'smtp.mydomain.org');

Parameters:

=over 4

=item SMS_USER (required)

BulkSMS username.

=item SMS_API_ID (required)

BulkSMS API ID.

=item SMTP (optional)

SMTP server to use when sending emails. If the server has not been
set the emails are sent using MIME::Lite sendmail option.

=item SENDMAIL_PATH (optional)

If no SMTP parameter is set the messages are sent using sendmail. The
SENDMAIL_PATH sets the path for sendmail executable.

=item FROM (optional)

From address to use when sending emails. The default address is
I<nobody@nodomain>.

=item SUBJECT (optional)

Subject to use when sending emails. The default subject is
I<Notification from ttmsg>. The subject string should be in UTF-8.

=item REPLACE_8BIT_SMS (optional)

Setting this to true turns on 8-bit replacement behaviour. This is useful
when your application produces 8-bit messages but you want to send only
7-bit SMS messages.

The option replaces 8-bit characters with a-z equivalents for all outbound
messages. Known characters are replaced with defined character(s), e.g. a,
AE. Unknown characters are replaced with _ (underscore).

=item REPLACE_8BIT_EMAIL (optional)

Equivalent to C<REPLACE_8BIT_SMS> but affects outgoing emails.

=item COST_ROUTE_SMS (optional)

Sends default value for BulkSMS route code I<cost_route>
(see also I<routing_group>). The possible values are 1, 2 and 3.
The default value defined by C<Net::SMS::BulkSMS> is 1.

This value is used when sending SMS messages.

=back

Returns the object reference. Dies in case of errors (missing required
parameters or failing to initialise database connection).

=cut

sub new {
	my ($class, %param) = @_;
	
	my $self = {};
	
	if ($param{'SMS_USER'} and $param{'SMS_API_ID'}) {
		# Required parameter(s) exist
		
		$self->{'SMS_USER'} = encode_base64($param{'SMS_USER'});
		$self->{'SMS_API_ID'} = encode_base64($param{'SMS_API_ID'});
		
		$self->{'SMS'} = Net::SMS::BulkSMS->new(
			username => $self->{'SMS_USER'},
			password => $self->{'SMS_API_ID'},
			signature => '',
			signature_datetime => 0,
			);
		}
	else {
		# Required parameters missing
		
		die("HY::Geo::ttmsg->new was called without required parameters SMS_USER and SMS_API_ID. Please consult documentation.");
		}

	if ($param{'SMTP'}) {
		$self->{'SEND_METHOD'} = 'smtp';
		$self->{'SEND_PARAMETER'} = $param{'SMTP'};
		}
	else {
		$self->{'SEND_METHOD'} = 'sendmail';
		if ($param{'SENDMAIL_PATH'}) {
			$self->{'SEND_PARAMETER'} = $param{'SENDMAIL_PATH'};
			}
		}
	
	if ($param{'FROM'}) {
		$self->{'FROM'} = $param{'FROM'};
		}
	else {
		$self->{'FROM'} = 'nobody@nodomain';
		}
	
	if ($param{'SUBJECT'}) {
		$self->{'SUBJECT'} = $param{'SUBJECT'};
		}
	else {
		$self->{'SUBJECT'} = 'Notification from ttmsg';
		}

	if ($param{'REPLACE_8BIT_SMS'}) {
		$self->{'REPLACE_8BIT_SMS'} = 1;
		}
	
	if ($param{'REPLACE_8BIT_EMAIL'}) {
		$self->{'REPLACE_8BIT_EMAIL'} = 1;
		}
	
	if ($param{'COST_ROUTE_SMS'}) {
		$self->{'COST_ROUTE_SMS'} = $param{'COST_ROUTE_SMS'};
		}
	
	$self->{'ERRORS'} = [];

	bless($self, $class);
	
	return $self;
	}

=item send(recipient, message)

Sends a message. If the recipient contains only characters +0123456789 the
message will be sent as SMS (see C<send_by_sms()>). If the recipient contains character @ the message
is interpreted as an email (see C<send_by_email()>).

 my $result1 = $ttmsg->send('0405526766', $this_message);
 my $result2 = $ttmsg->send('foo@bar', $this_message);

Parameters: recipient contact and message string. The message string should be
in UTF-8.

Returns true if message was sent, false in case of error. The error messages
can be read using C<get_errors()>.

=cut

sub send {
	my ($class, $recipient, $message) = @_;
	
	if ($recipient =~ /\@/) {
		# This is an email
		
		return $class->send_by_email($recipient, $message);
		}
	elsif ($recipient !~ /[^\d\+]/) {
		# This is a SMS
		
		return $class->send_by_sms($recipient, $message);
		}
	else {
		# Recipient was not a number or an email address
		
		$class->add_error("$recipient is not email or phone number");
		return;
		}
	}

=item send_by_email(recipient, message)

Sends an email using C<MIME::Lite>. This method should not be used
directly but via C<send()>.

Parameters: recipient contact and message string.
Returns true if message was sent, false in case of error. The error messages
can be read using C<get_errors()>.

=cut

sub send_by_email {
	my ($class, $recipient, $message) = @_;

	my $subject = $class->{'SUBJECT'};
	my $type;
	
	if ($class->{'REPLACE_8BIT_EMAIL'}) {
		# Send 7 bit email
		$subject = $class->replace_8bit($subject);
		$type = 'text/plain';
		$message = $class->replace_8bit($message);
		}
	else {
		# Send 8 bit email
		$subject = '=?UTF-8?B?'.encode_base64($subject, '').'?=';
		$type = 'text/plain; charset=UTF-8';
		# No need to change $message
		}
		
	my $ml = MIME::Lite->new(
		From => $class->{'FROM'},
		To => $recipient,
		Subject => $subject,
		Type => $type,
		Data => $message);
	
	# According to MIME::Lite documentation the SMTP sending croaks on
	# error. There is no configuration switch to just return failed status.
	my $send_ok;
	if ($class->{'SEND_PARAMETER'}) {
		$send_ok = $ml->send(
			$class->{'SEND_METHOD'},
			$class->{'SEND_PARAMETER'}
			);
		}
	else {
		$send_ok = $ml->send($class->{'SEND_METHOD'});
		}
	
	if (!$send_ok) {
		$class->add_error('Sending email failed.');
		return;
		}
	
	return 1;
	}
	
=item send_by_sms(recipient, message)

Sends an email using C<Net::SMS::BulkSMS>. This method should not be used
directly but via C<send()>.

Parameters: recipient contact and message string.
Returns true if message was sent, false in case of error. The error messages
can be read using C<get_errors()>.

=cut

sub send_by_sms {
	my ($class, $recipient, $message) = @_;

	if ($class->{'REPLACE_8BIT_SMS'}) {
		$message = $class->replace_8bit($message);
		}
	
	# Send message using Net::SMS::BulkSMS
	my @response = ();
	if ($class->{'COST_ROUTE_SMS'}) {
		# There is a cost route parameter
		
		@response = $class->{'SMS'}->send_sms(
			message=>$message, 
			msisdn=>$recipient,
			cost_route=>$class->{'COST_ROUTE_SMS'}
			);
		}
	else {
		# No cost route parameter (this is the default)
		@response = $class->{'SMS'}->send_sms(
			message=>$message, 
			msisdn=>$recipient
			);
		}
	if ($response[1]) {
		# No errors
		
		return 1;
		}
	else {
		# Errors present

		# Add BulkSMS error to error queue
		$class->add_error("BulkSMS error: ".$response[0]);
		return;
		}
	}

=item replace_8bit

Replaces 8-bit characters from given parameter with a) known substitutes or
b) underscore (_) if there is no known substitute.

Returns the 7-bit version of the string.

 $string_7bit = $ttmsg->replace_8bit($string_8bit);

=cut

sub replace_8bit {
	my ($class, $message) = @_;
	
	my $new = $message;
	
	my %XLATE = (
		'ä' => 'a', 'Ä' => 'A', 'á' => 'a', 'Á' => 'A', 'à' => 'a', 'À' => 'A',
		'ë' => 'e', 'Ẽ' => 'E', 'é' => 'e', 'É' => 'E', 'è' => 'e', 'È' => 'E',
		'ï' => 'i', 'Ï' => 'I', 'í' => 'i', 'Í' => 'I', 'ì' => 'i', 'Ì' => 'I',
		'ñ' => 'n', 'Ñ' => 'N',
		'ö' => 'o', 'Ö' => 'O', 'ó' => 'o', 'Ó' => 'O', 'ò' => 'o', 'Ò' => 'O',
		'ü' => 'u', 'Ü' => 'U', 'ú' => 'u', 'Ú' => 'U', 'ù' => 'u', 'Ù' => 'U',
		'¿' => '?', '¡' => '!',
		'ß' => 'ss',
		);
	
	# Replace all known characters
	foreach my $t (keys %XLATE) {
		$new =~ s/$t/$XLATE{$t}/g;
		}
	
	# Replace all unknown characters (128-n)
	$new =~ s/[^\x00-\x7F]/_/g;
	
	return $new;
	}

=item add_error

Adds error to the array buffer. See C<get_errors()> and C<error_count()>.
Mainly for internal use.

 $ttmsg->add_error("The database connection has vanished");

Returns always true.

=cut

sub add_error {
	my ($class, $message) = @_;
	
	push(@{$class->{'ERRORS'}}, $message);
	
	return 1;
	}

=item get_errors

Empties and returns the error buffer array. See C<add_error()> and C<error_count()>.

 my @errors = $ttmsg->get_errors();
 
Returns the error array.

=cut

sub get_errors {
	my ($class) = @_;
	
	my @errors = @{$class->{'ERRORS'}};
	
	$class->{'ERRORS'} = [];
	
	return @errors;
	}

=item error_count

Returns the number of errors in the error buffer array. See C<add_error()> and
C<error_count()>.

 if ($ttmsg->error_count() > 0) {
   print STDERR "Errors present:\n";
   print join("\n", $ttmsg->get_errors());
   }
 else {
   print "No errors!\n";
   }

=cut

sub error_count {
	my ($class) = @_;
	
	return scalar(@{$class->{'ERRORS'}});
	}
	
1;

__END__

=back

=head1 BUGS

According to MIME::Lite documentation the SMTP sending croaks on
error. There is no configuration switch to just return failed status. Make sure
that your SMTP settings are correct or use sendmail.

=head1 AUTHOR

Matti Lattu, <matti@lattu.biz>

=head1 ACKNOWLEDGEMENTS

The code was created for the project FIXME.

=head1 LICENSE AND COPYRIGHT

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.

Copyright (C) 2011 Matti Lattu

=cut

