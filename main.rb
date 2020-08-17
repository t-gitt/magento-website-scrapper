#!/usr/bin/ruby

require 'nokogiri'
require 'byebug'
require 'open-uri'
require 'sqlite3'
require 'tty-prompt'
require 'tty-box'


############# MAINEMENU function to display Main Menu #############
def self.mainMenu

	############# initialize variables #############
	db = SQLite3::Database.new "magento.db"
	url = URI.open("https://magento-test.finology.com.my/")

	prompt = TTY::Prompt.new

	drawBox("MAINEMENU")
	puts ""
	prompt.select("Magneto Website Scrapper") do |menu|
	  menu.choice "Show All Products", -> { self.showAll(db) }
	  menu.choice "Update DB", -> { self.crawl(db, url) }
	  menu.choice "Search DB", -> { self.search(db) }
	  menu.choice "Wipe DB", -> { self.cleanDB(db) }
	  menu.choice "EXIT", -> { :quit }
	end
	puts ""
    db.close if db
end

def self.drawBox(text)
	box = TTY::Box.frame(width: 30, height: 10, align: :center, padding: 3, title: {top_left: %Q["#{text}"], bottom_right: "@t-gitt"}) do "Magneto Website Scrapper" end
	print box
end

############# MAINEMENU function to show all products #############
def self.showAll(db)
	begin
    
    stm = db.prepare "SELECT * FROM Products" 
    rs = stm.execute 
   	total = 0 
    rs.each do |row|
		puts("Name: #{row[1]}")
		puts("Price: #{row[2]}")
		puts("Description: #{row[3]}")
		puts("Extra Information: #{row[4]}")
		puts("Sku: #{row[5]}")
		puts("Rating: %#{row[6]}")
		puts("URL: %#{row[7]}")
		puts ""
		total = row[0]
		# puts("Page in progress: #{product_url[:category_url]}")


    end
	puts("Total Products: #{total}")
	puts ""
           
	rescue SQLite3::Exception => e 
	    
	    # puts "Exception occurred"
	    puts ""
	    puts e
	    puts "Please update DB first"
	    puts ""
	    
	ensure
	    stm.close if stm
	    db.close if db

	end
self.mainMenu
end

############# MAINEMENU function to search sqlite DB #############
def self.search(db)
	begin

    total = db.execute "SELECT COUNT(*) FROM Products"
	puts ""
	puts "#{total[0][0]} Products found in DB"
	puts ""
	puts "Enter your search query:"
	keyword = gets
	keyword = keyword.delete("\n")
	if keyword.split.count > 0
      
	    statement = %{SELECT * FROM Products WHERE name like "%#{keyword}%" OR sku="#{keyword}" OR id="#{keyword}" OR description like "%#{keyword}%" OR additional like "%#{keyword}%"}       
	    vals = db.execute statement
		if vals
			vals.each do |val|
				puts ""
				puts("Name: #{val[1]}")
				puts("Price: #{val[2]}")
				puts("Description: #{val[3]}")
				puts("Extra Information: #{val[4]}")
				puts("Sku: #{val[5]}")
				puts("Rating: %#{val[6]}")
				puts("URL: %#{val[7]}")
				puts ""
				# puts("Page in progress: #{product_url[:category_url]}")
				puts("Product ID: #{val[0]}")
				puts ""
			end
			puts "Total result: #{vals.count}"
			puts ""
			
		end
	end

    
	rescue SQLite3::Exception => e 
	    
	    # puts "Exception occurred"
	    puts e
	    
	ensure
	    db.close if db
	end
self.mainMenu
end

############# MAINEMENU function to wipe DB data #############
def self.cleanDB(db)
	begin
		puts "Wiping Database ..."
		
		sqlQuery =  "SELECT * FROM sqlite_master  WHERE type = 'table'"

		db.execute "DROP TABLE Products"

		puts "Database was wiped successfully...."

	rescue SQLite3::Exception => e 
	    
	    # puts "Exception occurred"
	    # puts e
	    
	ensure
	end
	
end

############# MAINEMENU function to parse data from website and store it in DB #############
def self.crawl(db, url)


	############# call cleanDB function to wipe DB #############
	self.cleanDB(db)

	############# initialize variables #############
	parsedPage = Nokogiri::HTML(url)

    db.execute "CREATE TABLE IF NOT EXISTS Products(id INTEGER PRIMARY KEY, name TEXT, price REAL, description TEXT, additional TEXT, sku TEXT UNIQUE, rating REAL, url TEXT)"

	

	$products_url = Array.new
	$products = Array.new
	$categories = Array.new


	############# call getCategories function to get categories #############
	self.getCategories(parsedPage)



	############# iterate through each category page & get products list ############# 
	$categories.each do |category|
		perpage = 36
		category_url = category[:url] + "?product_list_limit=#{perpage}"
		

		############# call scrapProductUrls function for each category ############# 
		self.scrapProductUrls(category_url)
	end
		

	

	############# iterate through each product page & get product's details ############# 
	if $products_url.count > 0
		id = db.last_insert_row_id.to_i	
		$products_url.each do |product_url|
		begin

			######### Start DB transaction ###########	

			db = SQLite3::Database.open "magento.db"
			db.transaction


			url = URI.open(product_url[:url])
			parsedPage = Nokogiri::HTML(url)


			############# find Extra Information table ############# 
			tables = parsedPage.search('table')
			if tables.count > 0
				
				table = tables.last
				cells = table.css('th, td')
				extraInfo = ""
				############# iterate through each row  & get product's Extra Information ############# 
				cells.each_slice(2) do |key, value|
						cell = "| #{key.text}: #{value.text} "
						extraInfo = extraInfo + cell
				end
			end
			
			############# define rating variables ############# 
			rate = parsedPage.css('div.rating-result').css('span').css('span')

			if rate.count > 0
				rate = rate[2].text 
			else
				rate = ''
			end

			############# define product object ############# 
			product = {
				name: parsedPage.css('h1.page-title').text.strip.delete("\n"),
				price: parsedPage.css('span.price')[0].text.delete("$").to_f,
				description: parsedPage.css('div#description').text.strip.delete("\n"),
				additional: extraInfo,
				sku: parsedPage.css('div.value')[0].text,
				rating: rate,
				url: product_url[:url]
			}

			############# update sqlite3 db ############# 
			id = id.to_i + 1
			nameProduct = product[:name]
			price = product[:price]
			description = product[:description]
			additional = product[:additional]
			sku = product[:sku]
			rating = product[:rating]

			if rating.empty?
				rating = "00"
			end
			db.execute %Q[INSERT INTO Products VALUES(#{id},"#{nameProduct}", #{price}, "#{description.gsub('"', "'")}", "#{additional}", "#{sku}", #{rating}, "#{product_url[:url]}")]

			############# commit transactio ############# 
			db.commit

			$products << product

			puts("Adding: #{sku} | #{product_url[:url]}")
			puts("Page in progress: #{product_url[:category_url]}")
			puts("Total Products: #{id}")
			puts ""

			rescue SQLite3::Exception => e 
		    
		    puts "Exception occurred"
		    puts e
	        db.rollback
		    
			ensure
			    db.close if db
			end
			
		end
	end

self.mainMenu

end

def self.getCategories(parsedPage)

		############# find category elements #############
		navBar = parsedPage.css('nav.ul.ui-menu')
		categories_elements = parsedPage.css('nav.navigation').css('ul').css('li.level1')

		############# get list of categories ############# 
		categories_elements.each do |category_element|
			category = {
				name: category_element.css('a').text,
				url: category_element.css('a')[0].attributes["href"].value
			}
			
		$categories << category
		end

end

############# list all products urls for each pagintation ############# 
def self.scrapProductUrls(category_url)

			url = URI.open(category_url)
			parsedPage = Nokogiri::HTML(url)

			product_cards = parsedPage.css('li.product-item')
			product_cards = product_cards.slice(0..product_cards.count - 3)

			product_cards.each do |product_card|
					
					product_url = {
						name: product_card.css('a.product-item-link').text.strip.delete("\n"),
						url:  product_card.css('a.product-item-link').css('a')[0].attributes["href"].value,
						category_url: category_url 
					}

					$products_url << product_url

			 end

			############# check if there is more pagintation ############# 
			if parsedPage.css('li.current').css('span').count > 0
				 isNext = parsedPage.css('a.next').text
				 current = parsedPage.css('li.current').css('span')[1].text
				 unless isNext == ""
				 	scrapProductUrls(category_url + "&p=#{current.to_i+1}")
				 end
			end
			
			 
end


mainMenu()



