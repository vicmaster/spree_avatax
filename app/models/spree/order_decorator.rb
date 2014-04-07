module Spree
  Order.class_eval do

    def commit_avatax_invoice
      begin
        matched_line_items = self.line_items.select do |line_item|
          line_item.taxable?
        end

        invoice_lines =[]
        line_count = 0

        discount = 0
        credits = self.adjustments.select {|a| a.amount<0}
        discount = -(credits.sum &:amount)
        matched_line_items.each do |matched_line_item|
          line_count = line_count + 1
          matched_line_amount = matched_line_item.price * matched_line_item.quantity
          invoice_line = Avalara::Request::Line.new(
              :line_no => line_count.to_s,
              :destination_code => '1',
              :origin_code => '1',
              :qty => matched_line_item.quantity.to_s,
              :amount => matched_line_amount.to_s,
              :discounted => true,
              :item_code => matched_line_item.variant.sku
          )
          invoice_lines << invoice_line
        end

        invoice_line = Avalara::Request::Line.new(
            :line_no => (line_count + 1).to_s,
            :destination_code => '1',
            :origin_code => '1',
            :qty => 1,
            :amount => self.ship_total.to_s,
            :tax_code => 'FR000000',
            :discounted => true,
            :item_code => 'SHIPPING'
        )
        invoice_lines << invoice_line

        invoice_addresses = []
        invoice_address = Avalara::Request::Address.new(
            :address_code => '1',
            :line_1 => self.ship_address.address1.to_s,
            :line_2 => self.ship_address.address2.to_s,
            :city => self.ship_address.city.to_s,
            :postal_code => self.ship_address.zipcode.to_s
        )
        invoice_addresses << invoice_address

        invoice = Avalara::Request::Invoice.new(
            :customer_code => self.email,
            :doc_date => Date.today,
            :doc_type => 'SalesInvoice',
            :company_code => AvataxConfig.company_code,
            :reference_code => self.number,
            :commit => 'true',
            :discount => discount
        )

        invoice.addresses = invoice_addresses
        invoice.lines = invoice_lines

        #Log request
        #logger.debug 'Avatax Request - '
        #logger.debug invoice.to_s


        invoice_tax = Avalara.get_tax(invoice)

        ship_tax = invoice_tax["tax_lines"].map{|line| line['tax'] if line['tax_code'] == 'FR000000' }.compact.first

        #Tax
        tax_adjustment = self.adjustments.new
        tax_adjustment.label = "Tax"
        tax_adjustment.originator_type = "Spree::TaxRate"
        tax_adjustment.amount = invoice_tax["total_tax"].to_f - ship_tax.to_f
        tax_adjustment.save!

        #ship tax
        if ship_tax.to_f > 0
          tax_adjustment = self.adjustments.new
          tax_adjustment.label = "Shipping Tax"
          tax_adjustment.originator_type = "Spree::TaxRate"
          tax_adjustment.amount = ship_tax
          tax_adjustment.save!
        end

        save!

      rescue => error
        logger.debug 'Avatax Commit Failed!'
        logger.debug error.to_s
      end

    end


  end
end