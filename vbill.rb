#!/usr/bin/env ruby
def vbill(statement, sendemail=false, pages=[1,2,3,4], path_to_emails="emails.dat")
    # read text from statement
    text = read_text(statement, pages)
    # due date
    due_date = get_due_date(text, statement)
    # total current charges
    total_current_charges = get_total_current_charges(text)
    # credit balance 
    credit_balance = get_credit_balance(text)
    # account charges
    account_charges = get_account_charges(text)
    # people charges
    people_charges = get_people_charges(text)
    # -----------------------------------------------------------------------
    if sendemail.class == String
        sendemail = sendemail.to_bool
    end
    cal_bill due_date, total_current_charges, credit_balance, account_charges, people_charges, sendemail, path_to_emails
end
def read_text(statement, pages)
    require 'rubygems'
    require 'pdf-reader'
    reader = PDF::Reader.new(statement)
    # read pages
    text = ""
    if pages.class == String
        pages = pages.split(",").map { |s| s.to_i }
    end
    for i in pages
        text += reader.page(i).text
    end
    text = text.gsub(" ", "")
    text = text.gsub(/pg\d*/,"")
    return text
end
def get_due_date(text, statement)
    # match for due date
    regex = Regexp.new(/(\d{2}\/\d{2}\/\d{2})/)
    mdata = regex.match(text)
    if mdata.nil?
        unsupported_format
    end
    due_date = mdata[1]
    # rename statement if necessary
    rename_statement statement, due_date
    return due_date
end
def get_total_current_charges(text)
    # match for total current charges
    regex = Regexp.new(/TotalCurrentCharges(-{0,1}\$\d{0,3}\.\d{2})/)
    mdata = regex.match(text)
    if mdata.nil?
        unsupported_format
    end
    # find total current charges in cents
    total_current_charges = mdata[1].gsub("\$","").to_f * 100
    return total_current_charges
end
def get_credit_balance(text)
    regex = Regexp.new(/CreditBalance(-{0,1}\$\d{0,3}\.\d{2})/)
    mdata = regex.match(text)
    if mdata.nil?
        unsupported_format
    end
    # find credit balance in cents
    credit_balance = mdata[1].gsub("\$","").to_f * 100
    return credit_balance
end
def get_account_charges(text)
    # match for account charges
    regex = Regexp.new(/AccountCharges\&Credits(-{0,1}\$\d{0,3}\.\d{2})/)
    mdata = regex.match(text)
    if mdata.nil?
        unsupported_format
    end
    # find account charges in cents
    account_charges = mdata[1].gsub("\$","").to_f * 100 
    return account_charges
end
def get_people_charges(text)
    # split text by into lines
    text = text.split("\n")
    # match for personal charges
    regex = Regexp.new(/(\d{3}-\d{3}-\d{4})(-{0,1}\$\d{0,3}\.\d{2})/)
    mdatas = text.map{|x| regex.match(x)}
    mdatas.delete_if{|x| x==nil}
    if mdatas.length == 0
        unsupported_format
    end
    # find charges in cents for each person
    people_charges = mdatas.map{ |x| [x[1], x[2].gsub("\$","").to_f * 100] }
    return people_charges
end
def rename_statement(statement, due_date)
    # ask whether to rename the statement to its due date
    due_date = due_date.split '/'
    due_date = due_date[2] + '-' + due_date[0] + '-' + due_date[1] + ".pdf"
    if !due_date.eql?(statement)
        user_intent = shall_change_name_to(due_date)
        if user_intent
            # change name of statement
            File.rename(statement, due_date)
            puts "The statement has successfully been renamed to its due date."
        end
    end
end

def shall_change_name_to(file_name)
    require 'highline/import'
    user_intent = ask('Do you want to change the name of the statement to "' + file_name + '"?'){
        # |q|
        # q.echo = "*"
    }
    if user_intent.class == HighLine::String # note that the class of user_intent is not String
        user_intent = user_intent.to_bool
    end
    return user_intent
end

def cal_bill(due_date, total_current_charges, credit_balance, account_charges, people_charges, sendemail, path_to_emails)
    # calculate final bill for each person
    avg_account_charges = (account_charges + credit_balance) / people_charges.length()
    avg_account_charges = avg_account_charges.ceil 
    # construct second part of the email body
    email_body2 = "\nAnd the following is a summary of the statement in case you are interested.\n\n"\
    "Total bill: $" + "%.2f" % (total_current_charges/100) + "\n"\
    "Credit Balance : $" + "%.2f" % (credit_balance/100) + "\n"\
    "Account charges: $" + "%.2f" % (account_charges/100) + "\n"
    people_charges.each{
        |x|
        email_body2 += x[0].to_s + " charges: $" + "%.2f" % (x[1]/100) + "\n"
    }
    email_body2 += "\nIf you have any question about the bill, please let me know ASAP, "\
    "otherwise please remember to pay your part of bill before " + due_date + ".\n\nThanks!\n"
    #------------------------------------------------------------------------------------------------------
    final_bills = people_charges # people_charges will also be mutated, do not use it any more
    final_bills.each{ |x| x[1] += avg_account_charges }
    #-----------------------------------------------------------------------------------------------------
    # format en email content that you want to send to people
    email_subject = "Verizon Bill Due " + due_date
    # construct first part of the email body
    email_body1 = "Hello, everyone!\n\n"\
    "Our Verizon bill has arrived. The following is the specific bill for each of you.\n\n"
    actually_paid_bills = 0
    final_bills.each{ |x|
        email_body1 += x[0] + ": $" + "%.2f" % (x[1]/100) + "\n"
        actually_paid_bills += x[1]
    }
    email_body1 += "Total to pay VS Total bill: $" + "%.2f" % (actually_paid_bills/100) + " VS $" + "%.2f" % ((total_current_charges + credit_balance)/100) + ".\n" 
    email_body = email_body1 + email_body2
    # print emails subject and body for verification
    puts "************************************************************"
    print email_subject, "\n\n", email_body
    puts "************************************************************"
    if sendemail
        email_bills email_subject, email_body, path_to_emails
    end
end

def email_bills(subject, body, path_to_emails)
    require 'action_mailer'
    # ActionMailer::Base.default :from => 'Chuanlong Du <duchuanlong@gmail.com>'
    ActionMailer::Base.raise_delivery_errors = true
    ActionMailer::Base.delivery_method = :smtp
    # read in email address 
    member_emails = File.open(path_to_emails).readlines
    member_emails.each{ |x|
        x.strip!
    }
    # read in password for 'firedragon.du@gmail.com'
    password = read_password
    ActionMailer::Base.smtp_settings = {
        :address   => "smtp.gmail.com",
        :port      => 587,
        :domain    => "gmail.com",
        :authentication => :plain,
        :user_name      => "firedragon.du@gmail.com",
        :password       => password,
        :enable_starttls_auto => true
    }
    mail = ActionMailer::Base.mail(:to=>member_emails.join(','))
    mail.from = "firedragon.du@gmail.com"
    mail.reply_to = "duchuanlong@gmail.com"
    mail.subject = subject
    mail.body = body
    mail.deliver
    message = "Bills has been sent to the following email addresses.\n"
    member_emails.each do |x| 
        message += x + "\n"
    end
    puts message
end

def unsupported_format()
    abort "Bill information not found.\n"\
         "Make sure that you have specified the right page containing breakdown of charges.\n"
end

def read_password()
    require 'highline/import'
    return ask('Please enter the password for "firedragon.du@gmail.com":' + "\n"){
        |q|
        q.echo = "*"
    }
end

class String
    def to_bool
        return true if self == true || self =~ (/(true|t|yes|y|1)$/i)
        return false if self == false || self =~ (/(false|f|no|n|0)$/i)
        raise ArgumentError.new("invalid value for Boolean: \"#{self}\"")
    end
end

if __FILE__ == $0
    if ARGV.length == 1
        vbill ARGV[0]
        exit
    end
    if ARGV.length == 2
        vbill ARGV[0], ARGV[1]
        exit
    end
    if ARGV.length == 3
        vbill ARGV[0], ARGV[1], ARGV[2]
        exit
    end
    if ARGV.length == 4
        vbill ARGV[0], ARGV[1], ARGV[2], ARGV[3]
        exit
    end
    if ARGV.length >= 5
        puts 'Too many arguments!'
        exit
    end
end



